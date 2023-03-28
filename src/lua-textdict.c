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
#define MAX_DICT_INST 8

struct dict_node {
	struct dict_node *next;
	char * key;
	char * value;
};

struct dict_ctx {
	int ref;
	struct dict_node **buckets;
	size_t nbucket;
	size_t nnode;
};

struct dict_inst {
	int id;
	struct dict_ctx *ctx;
	int lock;
	pthread_key_t key;
	char name[64];
};

static struct dict_inst G_INST[MAX_DICT_INST];
static int dict_inst_num = 0;
static int lock;

static inline unsigned hash_key(const char* str) {
	unsigned seed = 131;
	unsigned hash = 0;
	while (*str) {
		hash = hash * seed + (*str++);
	}
	return hash;
}

static inline void _dict_add(struct dict_ctx *ctx, struct dict_node*node) {
	unsigned hash = hash_key(node->key);
	size_t idx = hash & (ctx->nbucket - 1);
	ctx->nnode++;
	node->next = ctx->buckets[idx];
	ctx->buckets[idx] = node;
}

static inline void dic_resize(struct dict_ctx *ctx) {
	struct dict_node **buckets, *node, *next;
	size_t nbucket, i;
	buckets = ctx->buckets;
	nbucket = ctx->nbucket;
	ctx->nbucket = (ctx->nbucket ? ctx->nbucket * 2 : 64);
	ctx->buckets = malloc(sizeof(*ctx->buckets) * ctx->nbucket);
	memset(ctx->buckets, 0, sizeof(*ctx->buckets) * ctx->nbucket);
	ctx->nnode = 0;
	for (i = 0; i < nbucket; i++) {
		for (node = buckets[i]; node; node = next) {
			next = node->next;
			_dict_add(ctx, node);
		}
	}
}

static void dict_add(struct dict_ctx *ctx, const char* key, const char* value) {
	if (ctx->nnode >= ctx->nbucket * 3 / 4) {
		dic_resize(ctx);
	}
	size_t ksize = strlen(key) + 1;
	size_t vsize = strlen(value) + 1;
	struct dict_node *node = malloc(sizeof(*node) + ksize + vsize);
	node->next = NULL;
	node->key = (char*)(node + 1);
	node->value = node->key + ksize;
	memcpy(node->key, key, ksize);
	memcpy(node->value, value, vsize);

	_dict_add(ctx, node);
}

static const char* dict_get(struct dict_ctx *ctx, const char* key) {
	struct dict_node *node;
	unsigned hash = hash_key(key);

	for (node = ctx->buckets[hash & (ctx->nbucket - 1)]; node; node = node->next) {
		if (strcmp(node->key, key) == 0) {
			return node->value;
		}
	}
	return NULL;
}

static void dict_free(struct dict_ctx *ctx ) {
	struct dict_node *node, *next;
	size_t i;
	for (i = 0; i < ctx->nbucket; i++) {
		for (node = ctx->buckets[i]; node; node = next) {
			next = node->next;
			free(node);
		}
	}
	free(ctx->buckets);
	free(ctx);
}

static struct dict_ctx* dict_new() {
	struct dict_ctx *ctx = malloc(sizeof(*ctx));
	ctx->ref = 1;
	ctx->buckets = NULL;
	ctx->nbucket = 0;
	ctx->nnode = 0;
	return ctx;
}

static inline struct dict_inst* dinst_get(int id) {
	return id < dict_inst_num ? (&G_INST[id]) : NULL;
}

static struct dict_ctx* dctx_grab(int id) {
	struct dict_ctx *ctx;
	struct dict_inst * inst = dinst_get(id);
	if (!inst) 	return NULL;

	LOCK(&inst->lock);
	ctx = inst->ctx;
	if (ctx) __sync_add_and_fetch(&ctx->ref, 1);
	UNLOCK(&inst->lock);

	return ctx;
}

static inline void dict_release(struct dict_ctx *ctx) {
	if (__sync_sub_and_fetch(&ctx->ref, 1) == 0) {
		printf("dict_release %p %d\n", ctx, ctx->ref);
		dict_free(ctx);
	}
}

static inline struct dict_ctx* dictctx_check(int id) {
	struct dict_inst * inst = dinst_get(id);
	if (!inst) return NULL;

	struct dict_ctx * ctx;
repeat:
	ctx = (struct dict_ctx *)pthread_getspecific(inst->key);
	if (ctx != inst->ctx) {
		struct dict_ctx *nctx = dctx_grab(id);
		pthread_setspecific(inst->key, nctx);
		if (ctx) dict_release(ctx);
		goto repeat;
	}
	return ctx;
}

static int dict_change(int id, struct dict_ctx *ctx) {
	struct dict_ctx * old;
	struct dict_inst * inst = dinst_get(id);
	if (!inst) {
		dict_release(ctx);
		return -1;
	}

	LOCK(&inst->lock);
	for (;;) {
		old = inst->ctx;
		if (__sync_bool_compare_and_swap(&inst->ctx, old, ctx)) {
			break;
		}
	}
	UNLOCK(&inst->lock);

	if (old) dict_release(old);
	return 0;
}

static void __attribute__((destructor)) dl_release() {
	int idx;
	for (idx = 0; idx < dict_inst_num; idx++) {
		struct dict_inst *inst = &G_INST[idx];

		pthread_key_delete(inst->key);
		if (inst->ctx) dict_free(inst->ctx);
	}
}

static struct dict_inst* dinst_alloc(const char* name) {
	int idx;
	for (idx = 0; idx < dict_inst_num; idx++) {
		struct dict_inst *inst = &G_INST[idx];
		if (strncmp(inst->name, name, sizeof(inst->name)) == 0) {
			return inst;
		}
	}

	LOCK(&lock);
	for (idx = 0; idx < dict_inst_num; idx++) {
		struct dict_inst *inst = &G_INST[idx];
		if (strncmp(inst->name, name, sizeof(inst->name)) == 0) {
			UNLOCK(&lock);
			return inst;
		}
	}
	if (dict_inst_num >= MAX_DICT_INST) {
		UNLOCK(&lock);
		return NULL;
	}
	struct dict_inst *inst = &G_INST[dict_inst_num];
	inst->id = dict_inst_num;
	inst->ctx = NULL;
	inst->lock = 0;
	pthread_key_create(&inst->key, NULL);
	strncpy(inst->name, name, sizeof(inst->name));
	inst->name[sizeof(inst->name) - 1] = '\0';
	__sync_synchronize();
	dict_inst_num++;

	UNLOCK(&lock);
	return inst;
}

static int dctx_gc(lua_State *L) {
	struct dict_ctx **ctx = lua_touserdata(L, 1);
	if (*ctx)	dict_release(*ctx);
	return 0;
}

static int lload_dict(lua_State *L) {
	struct dict_ctx *ctx, **pctx;

	int id = luaL_checkinteger(L, 1);
	luaL_checktype(L, 2, LUA_TTABLE);

	pctx = lua_newuserdata(L, sizeof(*pctx));
	ctx = dict_new();
	*pctx = ctx;

	lua_createtable(L, 0, 1);
	lua_pushcfunction(L, dctx_gc); // for safe load
	lua_setfield(L, -2, "__gc");
	lua_setmetatable(L, -2);

	lua_pushnil(L);
	while (lua_next(L, 2)) {
		const char * key = luaL_checkstring(L, -2);
		const char * value = luaL_checkstring(L, -1);
		dict_add(ctx, key, value);
		lua_pop(L, 1);
	}
	lua_pop(L, 1);
	*pctx = NULL;
	if (dict_change(id, ctx) != 0) {
		luaL_error(L, "dict_inst not initialized %d", id);
	}
	return 0;
}

static int ldict_get(lua_State *L) {
	int id = luaL_checkinteger(L, 1);
	const char * key = luaL_checkstring(L, 2);

	struct dict_ctx *ctx = dictctx_check(id);
	if (!ctx) {
		luaL_error(L, "dict_inst not initialized %d", id);
	}
	const char* value = dict_get(ctx, key);
	if (!value) {
		lua_pushnil(L);
	} else {
		lua_pushstring(L, value);
	}
	return 1;
}

static int ldict_getall(lua_State *L) {
	int id = luaL_checkinteger(L, 1);
	struct dict_ctx *ctx = dictctx_check(id);
	if (!ctx) {
		luaL_error(L, "dict_inst not initialized %d", id);
	}
	lua_newtable(L);
	unsigned i;
	for (i = 0; i < ctx->nbucket; i++) {
		struct dict_node *node;
		for (node = ctx->buckets[i]; node; node = node->next) {
			lua_pushstring(L, node->key);
			lua_pushstring(L, node->value);
			lua_rawset(L, -3);
		}
	}
	return 1;
}

static int lnew_dict(lua_State *L) {
	const char *name = luaL_checkstring(L, 1);
	struct dict_inst * inst = dinst_alloc(name);
	if (!inst) {
		luaL_error(L, "dict_inst max limit %d", (int)MAX_DICT_INST);
	}
	lua_pushinteger(L, inst->id);
	return 1;
}

LUAMOD_API int luaopen_textdict_c(lua_State *L) {
	luaL_Reg l[] = {
		{"query", lnew_dict},
		{"load", lload_dict},
		{"get", ldict_get},
		{"getall", ldict_getall},
		{NULL, NULL}
	};
	luaL_newlib(L, l);
	return 1;
}
