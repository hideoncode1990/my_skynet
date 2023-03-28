#define LUA_LIB
#include <unistd.h>
#include <lua.h>
#include <lauxlib.h>
#include "malloc_hook.h"
#include "jemalloc.h"

static int
lmemctl_int64(lua_State * L) {
	size_t allocated, active, mapped, metadata;
	uint64_t epoch = 1;
	size_t sz = sizeof(epoch);
	je_mallctl("epoch", &epoch, &sz, &epoch, sz);

	sz = sizeof(sz);
	je_mallctl("stats.allocated", &allocated, &sz, NULL, 0);		// total bytes of allocated
	je_mallctl("stats.active", &active, &sz, NULL, 0);			// total bytes of active pages
	je_mallctl("stats.mapped", &mapped, &sz, NULL, 0);		// total bytes of active pages
	je_mallctl("stats.metadata", &metadata, &sz, NULL, 0);	// total bytes of metadata

	size_t used_memory = malloc_used_memory();
	size_t memory_block = malloc_memory_block();

	lua_pushinteger(L, allocated);
	lua_pushinteger(L, active);
	lua_pushinteger(L, mapped);
	lua_pushinteger(L, metadata);
	lua_pushinteger(L, used_memory);
	lua_pushinteger(L, memory_block);
	return 6;
}

static int
lmemhelp_pid(lua_State *L) {
	lua_pushinteger(L, getpid());
	return 1;
}

static int
lmemhelp_pagesize(lua_State *L) {
	lua_pushinteger(L, getpagesize());
	return 1;
}

static int
lmemhelp_processors(lua_State *L) {
	lua_pushinteger(L, sysconf(_SC_NPROCESSORS_ONLN));
	return 1;
}

static void write_cb(void * data, const char * str) {
	luaL_Buffer* b = (luaL_Buffer*)data;
	luaL_addstring(b, str);
}
static int
lmemhelp_printstat(lua_State* L) {
	const char* opts = lua_tostring(L, 1);
	luaL_Buffer b;
	luaL_buffinit(L, &b);
	je_malloc_stats_print(write_cb, &b, opts);
	luaL_pushresult(&b);
	return 1;
}

LUAMOD_API int
luaopen_memhelp_c(lua_State * L) {
	luaL_checkversion(L);
	struct luaL_Reg lib[] = {
		{"jemalloc", lmemctl_int64},
		{"pid", lmemhelp_pid},
		{"pagesize", lmemhelp_pagesize},
		{"processors", lmemhelp_processors},
		{"printstat", lmemhelp_printstat},
		{NULL, NULL}
	};
	luaL_newlib(L, lib);
	return 1;
}
