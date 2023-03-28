#define LUA_LIB

#include <assert.h>
#include <vector>
#include <lua.hpp>

#if defined(__SSE4_2__)
#  define RAPIDJSON_SSE42
#elif defined(__SSE2__)
#  define RAPIDJSON_SSE2
#endif

#include "rapidjson/rapidjson.h"
#include "rapidjson/reader.h"
#include "rapidjson/writer.h"
#include "rapidjson/stringbuffer.h"
#include "rapidjson/error/en.h"
extern "C" {
#include "skynet_malloc.h"
}

using namespace rapidjson;

class SkynetAllocator {
public:
	static const bool kNeedFree = true;
	void* Malloc(size_t size) {
		if (size) //  behavior of malloc(0) is implementation defined.
			return skynet_malloc(size);
		else
			return NULL; // standardize to returning NULL.
	}
	void* Realloc(void* originalPtr, size_t originalSize, size_t newSize) {
		(void)originalSize;
		if (newSize == 0) {
			skynet_free(originalPtr);
			return NULL;
		}
		return skynet_realloc(originalPtr, newSize);
	}
	static void Free(void *ptr) { skynet_free(ptr); }
};

typedef GenericStringBuffer<UTF8<char>, SkynetAllocator> SkynetStringBuffer;
typedef Writer<SkynetStringBuffer, UTF8<char>, UTF8<char>, SkynetAllocator, kWriteDefaultFlags> SkynetWriter;
typedef GenericReader<UTF8<char>, UTF8<char>, SkynetAllocator> SkynetReader;

static void json_encode_value(lua_State* L, SkynetWriter& writer);
static void json_encode_array(lua_State* L, SkynetWriter& writer);
static void json_encode_object(lua_State* L, SkynetWriter& writer);

static int push_error(lua_State *L, const char *fmt, ...) {
	va_list argp;
	va_start(argp, fmt);
	luaL_where(L, 1);
	lua_pushvfstring(L, fmt, argp);
	va_end(argp);
	lua_concat(L, 2);
	return 1;
}

static bool is_table_array(lua_State* L) {
	size_t len = lua_rawlen(L, -1);
	if (len > 0) {
		lua_pushinteger(L, len);
		if (lua_next(L,-2) == 0) {
			return true;
		} else {
			lua_pop(L,2);
		}
	}
	return false;
}

void json_encode_value(lua_State* L, SkynetWriter& writer) {
	int tp = lua_type(L, -1);
	switch (tp) {
	case LUA_TNIL:
		writer.Null();
		break;
	case LUA_TBOOLEAN: {
		int b = lua_toboolean(L, -1);
		writer.Bool(!!b);
	}
	break;
	case LUA_TSTRING: {
		size_t len = 0;
		const char* s = lua_tolstring(L, -1, &len);
		writer.String(s, len);
	}
	break;
	case LUA_TNUMBER:{
		int isnum;
		int64_t v=lua_tointegerx(L,-1,&isnum);
		if (isnum) {
			writer.Int64(v);
		} else {
			writer.Double(lua_tonumber(L, -1));
		}
	}
	break;
	case LUA_TTABLE: {
		if (is_table_array(L)) {
			json_encode_array(L, writer);
		} else {
			json_encode_object(L, writer);
		}
	}
	break;
	default:
		luaL_error(L, "cant encode value of type: %s", lua_typename(L, tp));
	}
}

void json_encode_array(lua_State* L, SkynetWriter& writer) {
	assert(lua_type(L, -1) == LUA_TTABLE);
	size_t len = lua_rawlen(L, -1);
	writer.StartArray();
	for (size_t i = 1; i <= len; ++i) {
		lua_rawgeti(L, -1, i);
		json_encode_value(L, writer);
		lua_pop(L, 1);
	}
	writer.EndArray();
}

void json_encode_object(lua_State* L, SkynetWriter& writer) {
	assert(lua_type(L, -1) == LUA_TTABLE);
	writer.StartObject();
	lua_pushnil(L);
	while (lua_next(L, -2) != 0) {
		size_t len = 0;
		lua_pushvalue(L, -2);
		const char* s = luaL_checklstring(L, -1, &len);
		writer.Key(s, len);
		lua_pop(L, 1);
		json_encode_value(L, writer);
		lua_pop(L, 1);
	}
	writer.EndObject();
}

struct Decodehandler{
	Decodehandler(lua_State *l):L(l){
		stack.reserve(8);
	}

	bool Null(){
		lua_pushnil(L);
		context.Submit(L);
		return true;
	}
	bool Bool(bool b){
		lua_pushboolean(L,b);
		context.Submit(L);
		return true;
	}
	bool Int(int i){
		lua_pushinteger(L,i);
		context.Submit(L);
		return true;
	}
	bool Uint(unsigned int u){
		lua_pushinteger(L,u);
		context.Submit(L);
		return true;
	}
	bool Int64(int64_t i){
		lua_pushinteger(L,i);
		context.Submit(L);
		return true;
	}
	bool Uint64(uint64_t u){
		if(u<=static_cast<uint64_t>(std::numeric_limits<lua_Integer>::max())){
			lua_pushinteger(L,static_cast<lua_Integer>(u));
		}else{
			lua_pushnumber(L,static_cast<lua_Number>(u));
		}
		context.Submit(L);
		return true;
	}
	bool RawNumber(const char* str, SizeType len,bool copy){
		lua_pushlstring(L,str,len);
		context.Submit(L);
		return true;
	}
	bool Double(double d){
		lua_pushnumber(L,static_cast<lua_Number>(d));
		context.Submit(L);
		return true;
	}
	bool String(const char* str, SizeType len,bool copy){
		lua_pushlstring(L,str,len);
		context.Submit(L);
		return true;
	}
	bool StartObject(){
		lua_createtable(L,0,0);
		stack.push_back(context);
		context=Ctx::Object();
		return true;
	}
	bool Key(const char* str, SizeType len,bool copy){
		lua_pushlstring(L,str,len);
		return true;
	}
	bool EndObject(SizeType count){
		context=stack.back();
		stack.pop_back();
		context.Submit(L);
		return true;
	}
	bool StartArray(){
		lua_createtable(L,0,0);
		stack.push_back(context);
		context=Ctx::Array();
		return true;
	}
	bool EndArray(SizeType count){
		context=stack.back();
		stack.pop_back();
		context.Submit(L);
		return true;
	}
private:
	struct Ctx{
		Ctx():index(1),fn(&fn_empty){}
		void Submit(lua_State *L){
			fn(L,this);
		}
		static  Ctx Object(){
			return Ctx(&fn_object);
		}
		static  Ctx Array(){
			return Ctx(&fn_array);
		}
	private:
		explicit Ctx(void (*f)(lua_State *L,Ctx *ctx)):index(1),fn(f){}
		static void fn_object(lua_State *L,Ctx *ctx){
			lua_rawset(L,-3);
		}
		static void fn_array(lua_State *L,Ctx *ctx){
			lua_rawseti(L,-2,ctx->index++);
		}
		static void fn_empty(lua_State *L,Ctx *ctx){

		}
		int index;
		void (*fn)(lua_State *L,Ctx *ctx);
	};
	lua_State *L;
	std::vector<Ctx> stack;
	Ctx context;
};

static int lua_encode_inner(lua_State *L){
	SkynetWriter *writer=(SkynetWriter*)lua_touserdata(L,1);
	json_encode_value(L, *writer);
	return 1;
}

static int json_encode(lua_State* L) {
	SkynetStringBuffer buf;
	int top = lua_gettop(L);
	for (int i = 1; i <= top; ++i) {
		SkynetWriter writer(buf);
		lua_pushvalue(L,lua_upvalueindex(1));
		lua_pushlightuserdata(L,&writer);
		lua_pushvalue(L, i);
		if(lua_pcall(L,2,0,0)!=0){
			push_error(L,"%s",lua_tostring(L,-1));
			goto on_error;
		}
		lua_pushlstring(L, buf.GetString(), buf.GetSize());
		buf.Clear();
	}
	return top;
on_error:
	lua_error(L);
	return 0;
}

static int json_decode(lua_State* L) {
	size_t len = 0;
	const char* jsontext = luaL_checklstring(L, 1, &len);
	SkynetReader reader;
	Decodehandler handler(L);
	StringStream stream(jsontext);
	reader.Parse(stream,handler);
	if (reader.HasParseError()) {
		ParseErrorCode err = reader.GetParseErrorCode();
		int offset = reader.GetErrorOffset();
		return luaL_error(L, "Parse failed at offset %d: %s", offset, GetParseError_En(err));
	}
	return 1;
}

extern "C" {
	LUAMOD_API int
	luaopen_rapidjson_c(lua_State* L) {
		luaL_checkversion(L);
		luaL_Reg lib[] = {
			{ "encode", json_encode },
			{ "decode", json_decode },
			{ NULL, NULL },
		};
		luaL_newlibtable(L,lib);
		lua_pushcfunction(L,lua_encode_inner);
		luaL_setfuncs(L,lib,1);
		return 1;
	}
}
