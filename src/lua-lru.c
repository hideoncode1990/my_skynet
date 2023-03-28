#define LUA_LIB
#include <stdlib.h>
#include <assert.h>
#include <stdint.h>
#include <string.h>

#include <lualib.h>
#include <lauxlib.h>

#define IN_FIFO 0
#define IN_LRU 1

struct lru_node {
	int64_t id;
	struct lru_node *list_prev, *list_next;
	struct lru_node *next, **pprev;
	int where;
	size_t hits;
};

struct hash_head {
	struct lru_node *first;
};

struct lru_store {
	struct hash_head *buckets;
	size_t nbucket;
	size_t nnode;

	struct lru_node fifo;
	size_t fifo_max;
	size_t fifo_count;

	struct lru_node lru;
	size_t lru_max;
	size_t lru_count;

	size_t mv_hits;
};

struct lru_query_ctx {
	int64_t qid;
	int64_t did;
};

static inline void __list_add(struct lru_node *new, struct lru_node *prev, struct lru_node *next) {
	next->list_prev = new;
	new->list_next = next;
	new->list_prev = prev;
	prev->list_next = new;
}

static inline void list_add(struct lru_node *new, struct lru_node *head) {
	__list_add(new, head, head->list_next);
}

static inline void __list_del(struct lru_node * prev, struct lru_node * next) {
	next->list_prev = prev;
	prev->list_next = next;
}

static inline void list_del(struct lru_node *entry) {
	__list_del(entry->list_prev, entry->list_next);
	entry->list_next = NULL;
	entry->list_prev = NULL;
}

static inline size_t hash_key(struct lru_store *s, int64_t id) {
	return (s->nbucket - 1)&id;
}

static inline void hash_add(struct lru_store *s, struct lru_node* node) {
	size_t hash = hash_key(s, node->id);
	struct hash_head* head = &s->buckets[hash];
	struct lru_node *first = head->first;

	s->nnode++;

	node->next = first;
	if (first)
		first->pprev = &node->next;
	head->first = node;
	node->pprev = &head->first;
}

static inline struct lru_node* hash_get(struct lru_store *s, int64_t id) {
	size_t hash = hash_key(s, id);
	struct hash_head* head = &s->buckets[hash];
	struct lru_node * node;
	for (node = head->first; node; node = node->next) {
		if (node->id == id) {
			return node;
		}
	}
	return NULL;
}

static void hash_del(struct lru_store *s, struct lru_node *node) {
	struct lru_node *next = node->next;
	struct lru_node **pprev = node->pprev;
	*pprev = next;
	if (next)
		next->pprev = pprev;
	node->next = NULL;
	node->pprev = NULL;
	s->nnode--;
}

static inline void hash_resize(struct lru_store *s) {
	struct hash_head *buckets;
	size_t nbucket, i;
	buckets = s->buckets;
	nbucket = s->nbucket;
	s->nbucket = (s->nbucket ? s->nbucket * 2 : 64);
	s->buckets = malloc(sizeof(*s->buckets) * s->nbucket);
	memset(s->buckets, 0, sizeof(*s->buckets) * s->nbucket);
	s->nnode = 0;
	for (i = 0; i < nbucket; i++) {
		struct lru_node  *node, *next;
		for (node = buckets[i].first; node; node = next) {
			next = node->next;
			hash_add(s, node);
		}
	}
}

static void lru_newnode(struct lru_store * s, struct lru_query_ctx *ctx) {
	if (s->nnode >= s->nbucket * 3 / 4) {
		hash_resize(s);
	}
	struct lru_node *node = malloc(sizeof(*node));
	node->id = ctx->qid;
	node->where = IN_FIFO;
	node->hits = 0;
	hash_add(s, node);
	list_add(node, &s->fifo);
	if (++s->fifo_count > s->fifo_max) {
		node = s->fifo.list_prev;
		ctx->did = node->id;

		s->fifo_count--;
		hash_del(s, node);
		list_del(node);
		free(node);
	}
}

static void lru_nodehits(struct lru_store *s, struct lru_node *node, struct lru_query_ctx *ctx) {
	node->hits++;
	if (node->where == IN_FIFO) {
		if (node->hits >= s->mv_hits) {
			list_del(node);
			s->fifo_count--;
			node->where = IN_LRU;
			list_add(node, &s->lru);
			if (++s->lru_count > s->lru_max) {
				node = s->lru.list_prev;
				ctx->did = node->id;

				s->lru_count--;
				hash_del(s, node);
				list_del(node);
				free(node);
			}
		}
	} else {
		list_del(node);
		list_add(node, &s->lru);
	}
}

static void lru_query(struct lru_store * s, struct lru_query_ctx *ctx) {
	if (s->nbucket > 0) {
		struct lru_node *node = hash_get(s, ctx->qid);
		if (node) {
			lru_nodehits(s, node, ctx);
			return;
		}
	}
	lru_newnode(s, ctx);
}

static void lru_init(struct lru_store * s, size_t fifo_max, size_t lru_max, size_t mv_hits) {
	s->buckets = NULL;
	s->nbucket = 0;
	s->nnode = 0;
	s->fifo.list_prev = s->fifo.list_next = &s->fifo;
	s->fifo_max = fifo_max;
	s->fifo_count = 0;
	s->lru.list_prev = s->lru.list_next = &s->lru;
	s->lru_max = lru_max;
	s->lru_count = 0;
	s->mv_hits = mv_hits;
}

static void lru_free(struct lru_store * s) {
	size_t i;
	for (i = 0; i < s->nbucket; i++) {
		struct hash_head* head = &s->buckets[i];
		struct lru_node *node, *next;
		for (node = head->first; node; node = next) {
			next = node->next;
			free(node);
		}
	}
	free(s->buckets);
}

static int l_lru_gc(lua_State *L) {
	struct lru_store * s = lua_touserdata(L, 1);
	lru_free(s);
	return 0;
}

static struct lru_store * check_lru(lua_State *L, int idx) {
	struct lru_store * s = lua_touserdata(L, idx);
	if (!s) {
		luaL_error(L, "expected lru_store but got a %s(%d)", luaL_typename(L, idx), idx);
	}
	return s;
}

static int l_lru_new(lua_State *L) {
	lua_Integer fifo_max = luaL_checkinteger(L, 1);
	lua_Integer lru_max = luaL_checkinteger(L, 2);
	lua_Integer mv_hits = luaL_optinteger(L, 3, 1);
	if (fifo_max < 1 || lru_max < 1) {
		luaL_error(L, "args error need #1>=1 and #2>=1");
	}
	struct lru_store * s = lua_newuserdata(L, sizeof(*s));
	lru_init(s, fifo_max, lru_max, mv_hits);
	lua_createtable(L, 0, 1);
	lua_pushcfunction(L, l_lru_gc);
	lua_setfield(L, -2, "__gc");
	lua_setmetatable(L, -2);
	return 1;
}

static int l_lru_query(lua_State *L) {
	struct lru_store * s = check_lru(L, 1);
	lua_Integer id = luaL_checkinteger(L, 2);
	struct lru_query_ctx ctx = {.qid = id, .did = 0};
	lru_query(s, &ctx);
	if (ctx.did > 0) {
		lua_pushinteger(L, ctx.did);
		return 1;
	}
	return 0;
}

static int l_lru_allid(lua_State *L) {
	struct lru_store * s = check_lru(L, 1);
	lua_createtable(L, s->fifo_count + s->lru_count, 0);
	size_t i, idx = 0;
	for (i = 0; i < s->nbucket; i++) {
		struct hash_head* head = &s->buckets[i];
		struct lru_node *node;
		for (node = head->first; node; node = node->next) {
			lua_pushinteger(L, node->id);
			lua_rawseti(L, -2, ++idx);
		}
	}
	return 1;
}

LUAMOD_API int
luaopen_lru_core(lua_State *L) {
	luaL_checkversion(L);

	luaL_Reg l[] = {
		{"new", l_lru_new},
		{"mark", l_lru_query},
		{"all", l_lru_allid},
		{NULL, NULL}
	};
	luaL_newlib(L, l);
	return 1;
}
