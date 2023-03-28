/*
email:hongling0@gmail.com
*/
#define LUA_LIB
#include "skynet.h"
#include "skynet_timer.h"

#include <inttypes.h>
#include <stdint.h>
#include <time.h>
#include <sys/time.h>

#include <lualib.h>
#include <lauxlib.h>

#define DAY_SECONDS (24 * 60 * 60)
#define HOUR_SECONDS (60 * 60)

struct time_zone_ctx {
	time_t init_time;
	int init_wday;
	long int gmt_off;
};

static struct time_zone_ctx CTX;
static void init_starttime(time_t sec){
	struct tm tm;
	struct time_zone_ctx ctx;
	localtime_r(&sec, &tm);
	ctx.gmt_off = tm.tm_gmtoff;
	ctx.init_time = (sec + tm.tm_gmtoff) / DAY_SECONDS * DAY_SECONDS;// midnight
	ctx.init_wday = tm.tm_wday;
	CTX=ctx;
}

static void __attribute__((constructor)) _constructor() {
	init_starttime(time(NULL));
}

static inline long int get_zonediff() {
	return CTX.gmt_off;
}

static uint32_t tick_offset = 0;

static inline int64_t core_now(){
	return skynet_now()+tick_offset;
}

static inline int64_t core_time(){
	return skynet_starttime()+core_now()/100;
}

static inline double core_time_decimal(){
	double ti=core_now();
	return skynet_starttime()+ti/100;
}

static int same_day(lua_State *L) {
	lua_Integer t1 = luaL_checkinteger(L, 1);
	lua_Integer t2 = luaL_checkinteger(L, 2);
	lua_Integer offset = luaL_optinteger(L, 3, 0);
	long int diff = get_zonediff();
	lua_pushboolean(L, (t1 + diff - offset) / DAY_SECONDS == (t2 + diff - offset) / DAY_SECONDS);
	return 1;
}

static int same_hours(lua_State *L) {
	lua_Integer t1 = luaL_checkinteger(L, 1);
	lua_Integer t2 = luaL_checkinteger(L, 2);
	lua_Integer offset = luaL_optinteger(L, 3, 0);
	lua_Integer hours = luaL_optinteger(L, 4, 1);
	long int diff = get_zonediff();
	lua_pushboolean(L, (t1 + diff - offset) / (HOUR_SECONDS*hours) == (t2 + diff - offset) / (HOUR_SECONDS*hours));
	return 1;
}

static int to_daysec(lua_State *L) {
	lua_Integer t1 = luaL_optinteger(L, 1, core_time());
	lua_Integer offset = luaL_optinteger(L, 2, 0);
	long int sec = (t1 +  get_zonediff() - offset) % DAY_SECONDS;
	lua_pushinteger(L, sec);
	return 1;
}

static int next_midnight(lua_State *L) {
	lua_Integer t1 = luaL_optinteger(L, 1, core_time());
	lua_Integer offset = luaL_optinteger(L, 2, 0);
	time_t tt = ((t1 + get_zonediff() - offset) / DAY_SECONDS + 1) * DAY_SECONDS;
	lua_pushinteger(L, tt-get_zonediff());
	return 1;
}

static int midnight(lua_State *L) {
	lua_Integer t1 = luaL_optinteger(L, 1, core_time());
	lua_Integer offset = luaL_optinteger(L, 2, 0);
	time_t tt = (t1 + get_zonediff() - offset) / DAY_SECONDS * DAY_SECONDS;
	lua_pushinteger(L, tt-get_zonediff());
	return 1;
}

static inline time_t time_get_wday(time_t ti) {
	time_t ti_midnight=(ti + get_zonediff()) / DAY_SECONDS * DAY_SECONDS;
	time_t diff = ti_midnight - CTX.init_time;
	diff=diff/DAY_SECONDS;
	time_t wday = CTX.init_wday + diff;
	wday = wday % 7;
	if (wday < 0) {
		wday = 7 + wday;
	}
	return wday;
}
static int get_wday(lua_State *L) {
	lua_Integer ti = luaL_optinteger(L, 1, core_time());
	lua_pushinteger(L, time_get_wday(ti));
	return 1;
}

static int
lua_systime_now(lua_State *L) {
	lua_pushinteger(L, core_now());
	return 1;
}

static int
lua_systime_time(lua_State *L) {
	lua_pushinteger(L, core_time());
	return 1;
}

static int
lua_systime_time_decimal(lua_State *L) {
	lua_pushnumber(L, core_time_decimal());
	return 1;
}

static int
lua_systime_offset(lua_State *L) {
	uint64_t offset = lua_tointeger(L, -1);
	tick_offset+=offset*100;
	lua_pushinteger(L,tick_offset);
	return 1;
}

static int
lua_debug_timeinit(lua_State *L) {
	time_t ti = lua_tointeger(L, -1);
	init_starttime(ti);
	return 0;
}

LUAMOD_API int
luaopen_time_core(lua_State * L) {
	luaL_checkversion(L);
	luaL_Reg lib[] = {
		{"same_hours", same_hours},
		{"same_day", same_day},
		{"next_midnight", next_midnight},
		{"midnight", midnight},
		{"get_wday", get_wday},
		{"to_daysec", to_daysec},
		{ "now", lua_systime_now },
		{ "time", lua_systime_time },
		{ "time_decimal", lua_systime_time_decimal },
		{ "time_elapse", lua_systime_offset },
		{ "debug_init", lua_debug_timeinit },
		{NULL, NULL}
	};
	luaL_newlib(L, lib);
#ifdef _DEBUG_DEFINE
	lua_pushliteral(L,"DEBUG_DEFINE");
	lua_pushboolean(L,1);
	lua_rawset(L,-3);
#endif
	return 1;
}
