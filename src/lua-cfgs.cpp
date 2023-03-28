#include <unordered_map>
#include <stdint.h>
#include <vector>
#include <mutex>
#include <memory>
#include <string.h>

extern "C"{
#include <lua.h>
#include <lauxlib.h>
}

#define INVALID_OFFSET 0xffffffff

#define VALUE_NIL 0
#define VALUE_INTEGER 1
#define VALUE_REAL 2
#define VALUE_BOOLEAN 3
#define VALUE_TABLE 4
#define VALUE_STRING 5
#define VALUE_INVALID 6


#define INDEX_PROXY2TABLE 1
#define INDEX_INDEX2PROXY 2
#define INDEX_PROXYMETA 3

struct document {
	uint32_t strtbl;
	uint32_t n;
	uint32_t index[1];
	// table[n]
	// strings
};

struct table{
	uint32_t dict;
	uint8_t type[1];
	/*
	types[dict]
	{
		field[1]=field[2],
		...
	}
	 */
};

#define DOC_BIT 32
#define TBL_BIT 32
#define DOC_ID(index) ((index)>>TBL_BIT)
#define TBL_ID(index) ((index)&((1ull<<TBL_BIT)-1))
#define MAKE_INDEX(doc_id,tbl_id) ((((uint64_t)doc_id)<<TBL_BIT)|(tbl_id))
#define nullptr NULL

struct proxy{
	uint64_t index;
};

struct doc_object{
	char *data;
	size_t size;
	doc_object(const void *d,size_t sz){
		size=sz;
		data=new char[sz];
		memcpy(data,d,sz);
	}
	const document *get(){ return (document*)data;	}
	~doc_object(){ delete []data;}
};

static inline const table* totable(std::shared_ptr<doc_object> doc_obj, uint32_t index){
	const document* doc=doc_obj->get();
	if (doc->index[index] == INVALID_OFFSET) {
		return nullptr;
	}
	return (const struct table *)((const char *)doc + sizeof(uint32_t)
		+ sizeof(uint32_t) + doc->n * sizeof(uint32_t) + doc->index[index]);
}

class rwlock {
	int write;
	int read;
public:
	rwlock(){	write=read=0;	}
	void rlock(){
		for (;;) {
			while(write) {	__sync_synchronize();}
			__sync_add_and_fetch(&read,1);
			if (write) {__sync_sub_and_fetch(&read,1);	} else { break;}
		}
	}
	void	wlock() {
		while (__sync_lock_test_and_set(&write,1)) {}
		while(read) { __sync_synchronize(); }
	}
	void	wunlock() { __sync_lock_release(&write); }
	void runlock() { __sync_sub_and_fetch(&read,1); }
};

class rlock_guard{
	rwlock& lock;
public:
	rlock_guard(rwlock& l):lock(l){lock.rlock();}
	~rlock_guard(){lock.runlock();}
};
class wlock_guard{
	rwlock& lock;
public:
	wlock_guard(rwlock& l):lock(l){lock.wlock();}
	~wlock_guard(){lock.wunlock();}
};

class cfgproxy{
	rwlock slots_lock;
	std::vector<std::shared_ptr<doc_object> > slots;

	rwlock name_lock;
	std::unordered_map<std::string, uint32_t> names;

	static cfgproxy *s_ins;
public:
	static cfgproxy& instance(){
		if(!s_ins){
			s_ins=new cfgproxy();
		}
		return *s_ins;
	}

	static void release(){
		if(s_ins){
			delete s_ins;
			s_ins=nullptr;
		}
	}

	void table_readfunc(proxy *p,void(*readfunc)(void *ud,uint32_t doc_id,const document *doc
		,uint32_t tbl_id,const table *t),void *ud)	{
		uint32_t doc_id = DOC_ID(p->index);
		uint32_t tbl_id = TBL_ID(p->index);
		do{
			rlock_guard guard(slots_lock);
			std::shared_ptr<doc_object> doc = slots.at(doc_id);
			if (!doc){
				break;
			}
			readfunc(ud, doc_id, doc->get(), tbl_id, totable(doc, tbl_id));
			return;
		}while (0);
		readfunc(ud, doc_id, nullptr, tbl_id, nullptr);
	}

	bool add_document(const std::string& name, std::shared_ptr<doc_object> doc) {
		uint32_t idx;
		do{
			{
				// name read lock
				rlock_guard guard(name_lock);
				auto it = names.find(name);
				if (it != names.end()){
					idx = it->second;
					break;
				}
			}
			{
				// name write lock{
				wlock_guard guard(name_lock);
				wlock_guard g(slots_lock);
				if(slots.size()<(1ull<<DOC_BIT)){
					auto it = names.find(name);
					if (it != names.end()){
						idx = it->second;
						break;
					}
					// write lock
					names.insert(std::make_pair(name, slots.size()));
					slots.push_back(doc);
					return true;
				}
				return false;;
			}
		} while (0);
		{
			// write lock
			wlock_guard guard(slots_lock);
			slots[idx] = doc;
			return true;
		}
	}

	uint32_t get_docid(const std::string& name){
		rlock_guard guard(name_lock);
		auto it=names.find(name);
		if (it != names.end()){
			return it->second;
		}
		return INVALID_OFFSET;
	}
	const std::shared_ptr<doc_object> get_doc(const std::string& name){
		rlock_guard guard(name_lock);
		auto it=names.find(name);
		if (it != names.end()){
			rlock_guard guard(slots_lock);
			return slots[it->second];
		}
		return std::shared_ptr<doc_object>();
	}
};
cfgproxy* cfgproxy::s_ins=nullptr;

extern "C" {
static void __attribute__((constructor)) cfgs_constructor() {
	cfgproxy::instance();
}
static void __attribute__((destructor)) cfgs_release() {
	cfgproxy::release();
}
}

static inline void create_proxy(lua_State *L, uint32_t doc_id,uint32_t tbl_id){
	uint64_t index=MAKE_INDEX(doc_id,tbl_id);
	lua_pushinteger(L,index);
	lua_rawget(L,lua_upvalueindex(INDEX_INDEX2PROXY));
	if(lua_isnil(L,-1)){
		lua_pop(L,1);

		struct proxy *p = (struct proxy *)lua_newuserdata(L, sizeof(*p));
		p->index = index;

		lua_pushvalue(L, lua_upvalueindex(INDEX_PROXYMETA));
		lua_setmetatable(L, -2);

		lua_pushinteger(L,index);
		lua_pushvalue(L,-2);
		lua_rawset(L,lua_upvalueindex(INDEX_INDEX2PROXY));
	}
}

static int lcfg_new(lua_State *L){
	size_t len;
	const char *name=luaL_checkstring(L, 1);
	const char *data = luaL_checklstring(L, 2, &len);
	std::shared_ptr<doc_object> doc(new doc_object(data,len));
	if(!cfgproxy::instance().add_document(name, doc)){
		luaL_error(L,"add max %d", 1ull<<DOC_BIT);
	}
	return 0;
}

static int lcfg_get(lua_State *L){
	const char *name = luaL_checkstring(L, 1);
	uint32_t doc_id = cfgproxy::instance().get_docid(name);
	if (doc_id == INVALID_OFFSET){
		lua_pushnil(L);
	}else{
		create_proxy(L, doc_id, 0);
	}
	return 1;
}

static inline float getfloat(const void *v) {
	union {
		uint32_t d;
		float f;
		uint8_t t[4];
	} test = { 1 };
	if (test.t[0] == 0) {
		// big endian
		test.d = *(const uint32_t *)v;
		test.d = test.t[0] | test.t[1] << 4 | test.t[2] << 8 | test.t[3] << 12;
		return test.f;
	}
	else {
		return *(const float *)v;
	}
}

static inline uint32_t getuint32(const void *v) {
	union {
		uint32_t d;
		uint8_t t[4];
	} test = { 1 };
	if (test.t[0] == 0) {
		// big endian
		test.d = *(const uint32_t *)v;
		return test.t[0] | test.t[1] << 4 | test.t[2] << 8 | test.t[3] << 12;
	}
	else {
		return *(const uint32_t *)v;
	}
}

static inline void pushvalue(lua_State *L, const void *v, int type, const struct document * doc,uint32_t doc_id) {
	switch (type) {
	case VALUE_NIL:
		lua_pushnil(L);
		break;
	case VALUE_INTEGER:
		lua_pushinteger(L, (int32_t)getuint32(v));
		break;
	case VALUE_REAL:
		lua_pushnumber(L, getfloat(v));
		break;
	case VALUE_BOOLEAN:
		lua_pushboolean(L, getuint32(v));
		break;
	case VALUE_TABLE:
		create_proxy(L, doc_id, getuint32(v));
		break;
	case VALUE_STRING:
		lua_pushstring(L, (const char *)doc + doc->strtbl + getuint32(v));
		break;
	default:
		luaL_error(L, "Invalid type %d at %p", type, v);
	}
}

struct copytbl_ctx{
	lua_State *L;
	int tbl_idx;
};

static inline void copytable(void *ud, uint32_t doc_id, const document *doc, uint32_t tbl_id, const table *t) {
	lua_State *L = ((struct copytbl_ctx *)ud)->L;
	int tbl_idx=((struct copytbl_ctx *)ud)->tbl_idx;
	const uint32_t * v = (const uint32_t *)((const char *)t + sizeof(uint32_t) + ((t->dict * 2 + 3) & ~3));
	for (uint32_t i = 0; i<t->dict; i++) {
		pushvalue(L, v++, t->type[2 * i], doc, doc_id);
		pushvalue(L, v++, t->type[2 * i + 1], doc, doc_id);
		lua_rawset(L, tbl_idx);
	}
}

#ifdef _LCFGS_CACAHE_STATISTIC
static int64_t cache_miss=0;
static int64_t cache_hits=0;
#endif

static inline struct proxy * check_table(lua_State *L, int idx){
	struct proxy *p = (struct proxy *)lua_touserdata(L, idx);
	if (!p){
		luaL_error(L, "expected a proxy but got a %s(%d)", luaL_typename(L, idx), idx);
	}
	lua_pushvalue(L, idx);
	lua_rawget(L, lua_upvalueindex(INDEX_PROXY2TABLE));
	if (lua_isnil(L, -1)){
		lua_newtable(L);

		lua_pushvalue(L,idx);
		lua_pushvalue(L,-2);
		lua_rawset(L,lua_upvalueindex(INDEX_PROXY2TABLE));

		copytbl_ctx ctx;
		ctx.L=L;
		ctx.tbl_idx=lua_gettop(L);
		cfgproxy::instance().table_readfunc(p, copytable, &ctx);
#ifdef _LCFGS_CACAHE_STATISTIC
		__sync_add_and_fetch(&cache_miss,1);
	}else{
		__sync_add_and_fetch(&cache_hits,1);
#endif
	}
	return p;
}

static int meta__index(lua_State *L){
	check_table(L, 1);
	lua_pushvalue(L, 2);
	lua_rawget(L, -2);
	return 1;
}

/*
static int meta__newindex(lua_State *L){
	check_table(L, 1);
	lua_pushvalue(L, 2);
	lua_pushvalue(L, 3);
	lua_rawget(L, -3);
	return 0;
}
*/

static int meta__len(lua_State *L){
	check_table(L, 1);
	lua_pushinteger(L, lua_rawlen(L, -1));
	return 1;
}

static int lnext(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	lua_settop(L, 2);  /* create a 2nd argument if there isn't one */
	if (lua_next(L, 1))
		return 2;
	else {
		lua_pushnil(L);
		return 1;
	}
}

static int meta__pairs(lua_State *L) {
	check_table(L, 1);
	lua_pushcfunction(L, lnext);
	lua_pushvalue(L, -2);
	lua_pushnil(L);
	return 3;
}

static int lcfg_clear(lua_State *L){
	int idx=lua_upvalueindex(INDEX_PROXY2TABLE);
	lua_pushnil(L);
	while (lua_next(L, idx) != 0) {
		// key value
		lua_pop(L, 1);
		lua_pushvalue(L, -1);
		lua_pushnil(L);
		// key key nil
		lua_rawset(L, idx);
		// key
	}
	return 0;
}

static int lcfg_doc(lua_State *L){
	const char * nm=luaL_checkstring(L,1);
	auto doc=cfgproxy::instance().get_doc(nm);
	if(!doc){
		return 0;
	}
	lua_pushlstring(L,doc->data,doc->size);
	return 1;
}

static int lcfg_statistics(lua_State *L){
#ifdef _LCFGS_CACAHE_STATISTIC
	lua_pushinteger(L,cache_hits);
	lua_pushinteger(L,cache_miss);
	return 2;
#else
	luaL_error(L,"unsupport Plz re compile this with _LCFGS_CACAHE_STATISTIC");
	return 0;
#endif
}

static inline void new_weak_table(lua_State *L,const char *mode){
	lua_createtable(L, 0, 1);	// weak meta table proxy:data{}
	lua_pushstring(L, mode);
	lua_setfield(L, -2, "__mode");
}

extern "C"{
	LUAMOD_API int
	luaopen_cfgs_core(lua_State *L){
		luaL_checkversion(L);

		luaL_Reg l[] = {
				{ "new",lcfg_new },
				{ "query",lcfg_get },
				{ "update",lcfg_clear },
				{ "doc",lcfg_doc },
				{"statistics",lcfg_statistics},
				{ nullptr, nullptr },
		};
		luaL_newlibtable(L,l);

		new_weak_table(L,"kv");	//INDEX_PROXY2TABLE
		//new_weak_table(L,"kv");	//INDEX_PROXY2TABLE
		new_weak_table(L,"v");	//INDEX_INDEX2PROXY


		luaL_Reg m[] = {
				{ "__index", meta__index },
				//{ "__newindex",meta__newindex},
				{ "__pairs", meta__pairs },
				{ "__len", meta__len },
				{ nullptr, nullptr }
		};
		luaL_newlibtable(L,m);	//INDEX_PROXYMETA

		lua_pushvalue(L, -3);
		lua_pushvalue(L, -3);
		lua_pushvalue(L, -3);
		luaL_setfuncs(L, m, 3);

		luaL_setfuncs(L, l, 3);
		return 1;
	}
}
