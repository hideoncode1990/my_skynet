/*
email:hongling0@gmail.com
*/
#define LUA_LIB

#include <inttypes.h>
#include <stdint.h>
#include <time.h>

#include <lualib.h>
#include <lauxlib.h>


#define UNIQ_MAIN_SHIFT 15  // 16384*2	appid
#define UNIQ_TIME_SHIFT 29  // 8.5 years*2
#define UNIQ_INCR_SHIFT 19  // 262144*2

#define UNIQ_MAIN (1UL<<UNIQ_MAIN_SHIFT)
#define UNIQ_TIME (1UL<<UNIQ_TIME_SHIFT)
#define UNIQ_INCR (1UL<<UNIQ_INCR_SHIFT)

#define UNIQ_MAIN_MASK ((UNIQ_MAIN-1)<<(UNIQ_INCR_SHIFT+UNIQ_TIME_SHIFT))
#define UNIQ_TIME_MASK ((UNIQ_TIME-1)<<(UNIQ_INCR_SHIFT))
#define UNIQ_INCR_MASK ((UNIQ_INCR-1))

static uint32_t main_id;
static uint64_t last_sec;
static uint64_t last_inc;
static volatile uint32_t inc;
static int lock = 0;


#define LOCK(l) while (__sync_lock_test_and_set(l,1)) {}
#define UNLOCK(l) do{__sync_lock_release(l);}while(0)

static inline uint64_t
genid() {
	LOCK(&lock);
	uint64_t now = (uint64_t)time(NULL);
	if (last_inc == inc) {
		if (last_sec == now) {
			UNLOCK(&lock);
			return 0;
		} else {
			last_sec = now;
			last_inc = inc;
		}
	}
	if (++inc >= UNIQ_INCR) {
		inc = 0;
	}
	uint64_t inc_id = inc;
	UNLOCK(&lock);

	return (((uint64_t)main_id << ( UNIQ_TIME_SHIFT + UNIQ_INCR_SHIFT)) & UNIQ_MAIN_MASK)
	       | ((now << (UNIQ_INCR_SHIFT))&UNIQ_TIME_MASK)
	       | (inc_id & UNIQ_INCR_MASK);
}

static inline const char*
uint64_str(uint64_t u, char tmp[17]) {
	static char c[] = {'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F'};
	int i = 0;
	for (; i < 16; i++) {
		tmp[i] = c[u >> (15 - i) * 4 & 0xf];
	}
	return tmp;
}

static int
luauniq_init(lua_State * L) {
	uint64_t id = (uint64_t)luaL_checkinteger(L, 1);
	if (id >= UNIQ_MAIN) {
		luaL_error(L, "main_id must less than %d", (int)(UNIQ_MAIN));
	}
	uint64_t start_inc=(uint64_t)luaL_optinteger(L,2,0)&UNIQ_INCR_MASK;
	main_id = id;
	last_sec = 0;
	if(inc==0){
		last_inc = start_inc;
		inc = start_inc;
	}
	return 1;
}

#define GEN_ID(val,L) \
do { val=genid();\
if(val==0)\
	luaL_error(L,"max support register %d uniqid per second",(int)(UNIQ_INCR-1));\
}while(0)

static int luauniq_genid(lua_State * L) {
	int64_t val;
	GEN_ID(val, L);
	lua_pushinteger(L, val);
	return 1;
}

static int luauniq_gennums(lua_State * L) {
	char tmp[36] = {0};
	int64_t val;
	lua_Integer bit = luaL_optinteger(L, 1, 10);
	GEN_ID(val, L);
	switch (bit) {
	case 16:
		sprintf(tmp, "%" PRIx64, val);
		break;
	case 10:
		sprintf(tmp, "%" PRIu64, val);
		break;
	case 8:
		sprintf(tmp, "%" PRIo64, val);
		break;
	default:
		luaL_error(L, "unsupport bit transform %d", bit);
		break;
	}
	lua_pushstring(L, tmp);
	return 1;
}

static int luauniq_genstr(lua_State *L) {
	int64_t val;
	char tmp[17] = {0};
	GEN_ID(val, L);
	uint64_str(val, tmp);
	lua_pushstring(L, tmp);
	return 1;
}

LUAMOD_API int
luaopen_uniq_c(lua_State * L) {
	luaL_checkversion(L);
	luaL_Reg lib[] = {
		{"init", luauniq_init},
		{"id", luauniq_genid},
		{"str", luauniq_genstr},
		{"num", luauniq_gennums},
		{NULL, NULL}
	};
	luaL_newlib(L, lib);
	return 1;
}

