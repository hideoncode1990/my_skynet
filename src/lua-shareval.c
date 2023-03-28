#define LUA_LIB
/*
hongling0@gmail.com
*/
#include <stdlib.h>
#include <string.h>
#include <lua.h>
#include <lauxlib.h>
#include <pthread.h>

#define LOCK(l) while (__sync_lock_test_and_set(l,1)) {}
#define UNLOCK(l) do{__sync_lock_release(l);}while(0)
#define MAX_INST 64


#define ST_STRING 0
#define ST_INTEGER 1
#define ST_DOUBLE 2
#define ST_NIL 3
#define ST_BOOLEAN 4

struct sval_t {
	int8_t type;
	int ref;
	union {
		char* s;
		int64_t i;
		double d;
		char b;
	};
};

struct sctx_t {
	struct sval_t *val;
	int lock;
	pthread_key_t key;
	pthread_once_t once;	// PTHREAD_ONCE_INIT is 0 glibc
};

static struct sctx_t INSTS[MAX_INST];

static void sval_release(struct sval_t * ctx) {
	if (__sync_sub_and_fetch(&ctx->ref, 1) == 0) {
		free(ctx);
	}
}
static void tls_release(void * d) {
	sval_release(d);
}

static __thread int _t_id;
static void tls_init() {
	struct sctx_t * ctx = &INSTS[_t_id];
	pthread_key_create(&ctx->key, tls_release);
}

static struct sctx_t * sctx_grab(int id) {
	struct sctx_t * ctx = &INSTS[id];
	_t_id = id;
	pthread_once(&ctx->once, tls_init);
	return ctx;
}

static void sval_update(int id, struct sval_t * val) {
	struct sctx_t * ctx = sctx_grab(id);
	struct sval_t *old;
	LOCK(&ctx->lock);
	old = ctx->val;
	ctx->val = val;
	UNLOCK(&ctx->lock);
	if (old) {sval_release(old);}
}

static struct sval_t * sval_check(int id) {
	struct sval_t *cur;
	struct sctx_t * ctx = sctx_grab(id);
	struct sval_t *old = pthread_getspecific(ctx->key);
	if (old == ctx->val) {
		return old;
	} else {
		LOCK(&ctx->lock);
		cur = ctx->val;
		__sync_add_and_fetch(&cur->ref, 1);
		pthread_setspecific(ctx->key, cur);
		UNLOCK(&ctx->lock);
		if (old) { sval_release(old);}
		return cur;
	}
}

static inline int lgrab_id(lua_State *L, int idx) {
	int id = luaL_checkinteger(L, idx);
	if (id >= MAX_INST) {
		luaL_error(L, "bad id %d @(%d),must less than %d", id, idx, MAX_INST);
	}
	return id;
}

static int lsval_update(lua_State *L) {
	struct sval_t* val = NULL;;
	int id = lgrab_id(L, 1);
	switch (lua_type(L, 2)) {
	case LUA_TNIL: {
		val = malloc(sizeof(*val));
		val->type = LUA_TNIL;
		break;
	}
	case LUA_TBOOLEAN: {
		val = malloc(sizeof(*val));
		val->type = ST_BOOLEAN;
		val->b = lua_toboolean(L, 2);
		break;
	}
	case LUA_TNUMBER: {
		val = malloc(sizeof(*val));
		if (lua_isinteger(L, 2)) {
			val->type = ST_INTEGER;
			val->i = lua_tointeger(L, 2);
		} else {
			val->type = ST_DOUBLE;
			val->d = lua_tonumber(L, 2);
		}
		break;
	}
	case LUA_TSTRING: {
		size_t len;
		const char * s = lua_tolstring(L, 2, &len);
		val = malloc(sizeof(*val) + len + 1);
		val->type = ST_STRING;
		memcpy(val->s, s, len);
		break;
	}
	default: {
		luaL_error(L, "not support type %s", luaL_typename(L, 2));
		break;
	}
	}
	val->ref = 1;
	sval_update(id, val);
	return 0;
}

static int lsval_query(lua_State *L) {
	int id = lgrab_id(L, 1);
	struct sval_t* val = sval_check(id);
	int throw = luaL_optinteger(L, 2, 0);
	if (!val) {
		if (throw)
			luaL_error(L, "%d not inited", id);
		else
			return 0;
	}
	switch (val->type) {
	case ST_STRING: {
		lua_pushstring(L, val->s);
		break;
	}
	case ST_INTEGER: {
		lua_pushinteger(L, val->i);
		break;
	}
	case ST_DOUBLE: {
		lua_pushnumber(L, val->d);
		break;
	}
	case ST_NIL: {
		lua_pushnil(L);
		break;
	}
	case ST_BOOLEAN: {
		lua_pushboolean(L, val->b);
		break;
	}
	default: {
		luaL_error(L, "not unexpected type %d", (int)val->type);
		break;
	}
	}
	return 1;
}

LUAMOD_API int luaopen_shareval_core(lua_State *L) {
	luaL_Reg l[] = {
		{"update", lsval_update},
		{"query", lsval_query},
		{NULL, NULL}
	};
	luaL_newlib(L, l);
	return 1;
}
