#define LUA_LIB

#include <limits>
#include <cmath>
#include <algorithm>

#include <lua.hpp>

//#include "ceil_objs.h"
//#include "ceil_find.h"
#include "ceil_map.h"

using namespace area;

static inline ceilmap& check_cm(lua_State *L, int idx) {
	ceilmap **cm = (ceilmap **)lua_touserdata(L, idx);
	if (!cm) {
		luaL_error(L, "expected a ceilmap but got a %s @(%d)", luaL_typename(L, idx), idx);
	}
	return **cm;
}

static inline ceil_ints& check_ints(storge_ceils<ceil_ints>& sc) {
	if (!sc) {
		throw std::logic_error("not inited");
	}
	return *sc;
}

static int push_error(lua_State *L, const char *fmt, ...) {
	va_list argp;
	va_start(argp, fmt);
	luaL_where(L, 1);
	lua_pushvfstring(L, fmt, argp);
	va_end(argp);
	lua_concat(L, 2);
	return 1;
}

static int lnew(lua_State *L) {
	lua_Integer maxx = luaL_checkinteger(L, 1);
	lua_Integer maxy = luaL_checkinteger(L, 2);
	if (maxx >= std::numeric_limits<uint16_t>::max() ||
	        maxy >= std::numeric_limits<uint16_t>::max() ||
	        maxx * maxy >= std::numeric_limits<uint16_t>::max()) {
		luaL_error(L, "args error");
	}
	ceilmap **cm = (ceilmap **)lua_newuserdata(L, sizeof(*cm));
	*cm = new ceilmap;
	(*cm)->c_objs.init((int)maxx, (int)maxy);
	lua_pushvalue(L, lua_upvalueindex(1));
	lua_setmetatable(L, -2);
	return 1;
}

static int ladd(lua_State *L) {
	ceilmap& cm = check_cm(L, 1);
	lua_Integer id = luaL_checkinteger(L, 2);

	double x = luaL_checknumber(L, 3);
	double y = luaL_checknumber(L, 4);
	double range = luaL_optnumber(L, 5, 0);
	try {
		fpoint pos(x, y);
		objopt::add(*cm.c_objs, id, pos, range);
	} catch (std::exception& e) {
		luaL_error(L, "exception  %s", e.what());
	}
	return 0;
}

static int ldel(lua_State *L) {
	ceilmap& cm = check_cm(L, 1);
	lua_Integer id = luaL_checkinteger(L, 2);
	if (objopt::del(*cm.c_objs, id) != 0) {
		luaL_error(L, "del failure %d", id);
	}
	return 0;
}

static int lmove(lua_State *L) {
	ceilmap& cm = check_cm(L, 1);
	lua_Integer id = luaL_checkinteger(L, 2);
	double x = luaL_checknumber(L, 3);
	double y = luaL_checknumber(L, 4);
	fpoint pos(x, y);
	if (objopt::move(*cm.c_objs, id, pos) != 0) {
		luaL_error(L, "move failure %d(%d,%d)", id, x, y);
	}
	return 0;
}

static bool less_cmp(const std::pair<int64_t, double>& lhs, const std::pair<int64_t, double>& rhs) {
	return lhs.second < rhs.second;
}

template <typename C>
struct callc_wrap {
	lua_State *L;
	C& c;
	point pos;
	std::vector<std::pair<int64_t, double>> res;
	int top;
#ifdef _CEIL_DEBUG
	int loc_count;
#endif
	callc_wrap(lua_State *l, C& _c, const fpoint&_pos) : L(l), c(_c), pos(point(_pos)) {
		lua_newtable(L);
		top = lua_gettop(l);
#ifdef _CEIL_DEBUG
		lua_newtable(L);
		loc_count = 0;
#endif
	}
	~callc_wrap() {
		int idx = 0;
		std::sort(res.begin(), res.end(), less_cmp);
		for (auto it = res.begin(); it != res.end(); it++) {
			lua_pushinteger(L, it->first);
			lua_rawseti(L, top, ++idx);
		}
	}
	void operator()(const point& pos, const ceil_vobjs_t& vobjs) {
		if (c(pos)) {
			for (auto it = vobjs.begin(); it != vobjs.end(); it++) {
				auto obj = *it;
				res.emplace_back(obj->id, calc_distance(pos, point(obj->pos)));
			}
#ifdef _CEIL_DEBUG
			location loc(pos);
			lua_pushinteger(L, loc.x);
			lua_rawseti(L, top + 1, ++loc_count);
			lua_pushinteger(L, loc.y);
			lua_rawseti(L, top + 1, ++loc_count);
#endif
		}
	}
	int calc_distance(const point &left, const point& right) const {
		return (left.x - right.x) * (left.x - right.x) + (left.y - right.y) * (left.y - right.y);
	}
};


static int lcalc(lua_State *L) {
	ceilmap& cm = check_cm(L, 1);
	const char * type = luaL_checkstring(L, 2);
	double dist_x = luaL_checknumber(L, 3);
	double dist_y = luaL_checknumber(L, 4);
	int check_safe = luaL_checknumber(L, 5);
	try {
		fpoint dist(dist_x, dist_y);
		lua_newtable(L);
		switch (*type) {
		case 'C': {
			double x = luaL_checknumber(L, 6);
			double y = luaL_checknumber(L, 7);
			double r = luaL_checknumber(L, 8);
			fpoint center(x, y);
			calc::p_in_circle c = {center, r};
			callc_wrap<decltype(c)> call(L, c, dist);
			fpoint min(x - r, y - r), max(x + r, y + r);
			objopt::calc(*cm.c_objs, check_ints(cm.c_area), call, min, max, check_safe);
		}
		break;
		case 'P': {
			luaL_checktype(L, 6, LUA_TTABLE);
			point V[20];

			fpoint max(std::numeric_limits<double>::min(), std::numeric_limits<double>::min());
			fpoint min(std::numeric_limits<double>::max(), std::numeric_limits<double>::max());
			int len = 0;

			lua_pushnil(L);
			while (lua_next(L, 6) != 0) {
				if (len == sizeof(V) / sizeof(V[0])) {
					luaL_error(L, "max support %d ceils sides poly", (int)sizeof(V) / sizeof(V[0]));
				}
				luaL_checktype(L, -1, LUA_TTABLE);
				lua_getfield(L, -1, "x");
				double x = luaL_checknumber(L, -1);
				lua_pop(L, 1);
				if (x < min.x) min.x = x;
				if (x > max.x) max.x = x;

				lua_getfield(L, -1, "y");
				double y = luaL_checknumber(L, -1);
				lua_pop(L, 1);
				if (y < min.y) min.y = y;
				if (y > max.y) max.y = y;

				V[len++] = point(fpoint(x, y));
				lua_pop(L, 1);
			}

			if (len < 3) {
				luaL_error(L, "min support 3 sides poly");
			}
			V[len] = V[0];
			calc::p_in_poly c(len, V);
			callc_wrap<decltype(c)> call(L, c, dist);
			objopt::calc(*cm.c_objs, check_ints(cm.c_area), call, min, max, check_safe);
			break;
		}
		default:
			luaL_error(L, "unkown calc type");
			break;
		}
	} catch (std::exception& e) {
		push_error(L, "area_init exception %s", e.what());
		goto on_error;
	}
#ifdef _CEIL_DEBUG
	return 2;
#else
	return 1;
#endif
on_error:
	lua_error(L);
	return 0;
}


static int larea_init(lua_State * L) {
	size_t len;
	ceilmap& cm = check_cm(L, 1);
	const char * buf = luaL_checklstring(L, 2, &len);
	try {
		cm.c_area.init(buf);
		if (cm.c_area->x != cm.c_objs->x || cm.c_area->y != cm.c_objs->y) {
			cm.c_area.reset();
			throw std::logic_error("size error");
		}
	} catch (std::exception& e) {
		push_error(L, "area_init exception %s", e.what());
		goto on_error;
	}
	return 0;
on_error:
	lua_error(L);
	return 0;
}

static int
larea_get(lua_State * L) {
	ceilmap& cm = check_cm(L, 1);
	double width = luaL_checknumber(L, 2);
	double height = luaL_checknumber(L, 3);
	fpoint pos(width, height);
	try {
		auto val = intopt::check(check_ints(cm.c_area), location(pos));
		if (val < 0) {
			throw std::logic_error("out of range(" + std::to_string((long double)width) + "," + std::to_string((long double)height) + ")");
		}
		lua_pushboolean(L, val > 0);
		return 1;
	} catch (std::exception& e) {
		push_error(L, "larea_get exception %s", e.what());
		goto on_error;
	}
on_error:
	lua_error(L);
	return 0;
}

static int lstop_init(lua_State * L) {
	size_t len;
	ceilmap& cm = check_cm(L, 1);
	const char * buf = luaL_checklstring(L, 2, &len);
	try {
		cm.c_stop.init(buf);
		if (cm.c_stop->x != cm.c_objs->x || cm.c_stop->y != cm.c_objs->y) {
			cm.c_stop.reset();
			throw std::logic_error("size error");
		}
	} catch (std::exception& e) {
		push_error(L, "lstop_init exception %s", e.what());
		goto on_error;
	}
	return 0;
on_error:
	lua_error(L);
	return 0;
}

static int
lstop_get(lua_State * L) {
	ceilmap& cm = check_cm(L, 1);
	double width = luaL_checknumber(L, 2);
	double height = luaL_checknumber(L, 3);
	fpoint pos(width, height);
	try {
		auto val = intopt::check(check_ints(cm.c_stop), location(pos));
		if (val < 0) {
			throw std::logic_error("out of range(" + std::to_string((long double)width) + "," + std::to_string((long double)height) + ")");
		}
		lua_pushboolean(L, val > 0);
		return 1;
	} catch (std::exception& e) {
		push_error(L, "larea_get exception %s", e.what());
		goto on_error;
	}
on_error:
	lua_error(L);
	return 0;
}

static int
lceil_info(lua_State * L) {
	intopt::storge storge;
	lua_pushnil(L);
	while (lua_next(L, 1) != 0) {
		const char * key = luaL_checkstring(L, -2);
		const char * content = luaL_checkstring(L, -1);
		storge.add(key, content);
		lua_pop(L, 1);
	}
	intopt::storge::instance().swap(storge);
	storge_ceils<ceil_ints>::clear_storge();
	return 0;
}

/*static int do_export(lua_State * L, void(*call)(ceilmap&, int, seri::writer&), ceilmap& cm, int zero, uint8_t* buf, size_t sz) {
try {
seri::writer b(buf, sz);
call(cm, zero, b);
lua_pushlstring(L, (const char*)buf, b.size());
return 0;
} catch (std:: exception& e) {
push_error(L, "load exception %s" , e.what());
}
return 1;
}
*/

/*
static int
lslotmap_export(lua_State * L) {
ceilmap& cm = check_cm(L, 1);
const char *s = luaL_optstring(L, 2, "" );
int type = s[0];
int zero = luaL_optinteger(L, 3, 1);
uint8_t buf[1024 * 1024];
int err = 0;

switch (type) {
case cmflag::proto_string::TYPE: {
err = do_export(L, cmflag::export_proto<cmflag::proto_string>, cm, zero, buf, sizeof(buf));
break;
}
case cmflag::proto_binary::TYPE: {
err = do_export(L, cmflag::export_proto<cmflag::proto_binary>, cm, zero, buf, sizeof(buf));
break;
}
default:
luaL_error(L, "unknow type %d", type);
break;
}
if (err) {
lua_error(L);
}
return 1;
}*/

static int
lbinary2string(lua_State * L) {
	size_t len;
	const char *buf = luaL_checklstring(L, -1, &len);
	{
		try {
			seri::reader in((const uint8_t*)buf, len);
			uint8_t tmp[1024 * 1024];
			seri::writer out(tmp, sizeof(tmp));
			intopt::proto_transform<intopt::proto_binary, intopt::proto_string>(in, out);
			lua_pushlstring(L, (const char*)tmp, out.size());
			return 1;
		} catch (std::exception& e) {
			push_error(L, "load exception %s", e.what());
			goto on_error;
		}
	}
on_error:
	lua_error(L);
	return 0;
}

static int
lstring2binary(lua_State * L) {
	size_t len;
	const char *buf = luaL_checklstring(L, -1, &len);
	{
		try {
			seri::reader in((const uint8_t*)buf, len);
			uint8_t tmp[1024 * 1024];
			seri::writer out(tmp, sizeof(tmp));
			intopt::proto_transform<intopt::proto_string, intopt::proto_binary>(in, out);
			lua_pushlstring(L, (const char*)tmp, out.size());
			return 1;
		} catch (std::exception& e) {
			push_error(L, "load exception %s", e.what());
			goto on_error;
		}
	}
on_error:
	lua_error(L);
	return 0;
}

static int
lgc(lua_State * L) {
	ceilmap& cm = check_cm(L, 1);
	delete &cm;
	return 0;
}

struct stop_loc {
	ceilmap& CM;
	lua_State *L;
	int result;
	stop_loc(ceilmap& cm, lua_State *l) : CM(cm), L(l), result(0) {}
	bool operator()(int ceil_x, int ceil_y, double stopx, double stopy, double lstopx, double lstopy) {
		location loc(ceil_x, ceil_y);
		int val = intopt::check(*CM.c_stop, loc);
		if (val > 0) {
			location lo(point(stopx, stopy));
			val = intopt::check(*CM.c_stop, location(lo));
			if (val > 0) {
				lua_pushnumber(L, lstopx / OPPS);
				lua_pushnumber(L, lstopy / OPPS);
			} else {
				lua_pushnumber(L, stopx / OPPS);
				lua_pushnumber(L, stopy / OPPS);
			}
			result = 1;
			//assert(cmflag::check_ceil(CM, CM.c_stop, point(stopx, stopy)) == 0);
			return false;
		}
		return true;
	}
};

static int lcheckstop(lua_State * L) {
	ceilmap& cm = check_cm(L, 1);
	int x1 = (lua_Integer)(luaL_checknumber(L, 2) * OPPS);
	int y1 = (lua_Integer)(luaL_checknumber(L, 3) * OPPS);
	int x2 = (lua_Integer)(luaL_checknumber(L, 4) * OPPS);
	int y2 = (lua_Integer)(luaL_checknumber(L, 5) * OPPS);
	x1 = std::min(std::max(x1, 0), ((int)cm.c_stop->x - 1) * OPPS);
	x2 = std::min(std::max(x2, 0), ((int)cm.c_stop->x - 1) * OPPS);
	y1 = std::min(std::max(y1, 0), ((int)cm.c_stop->y - 1) * OPPS);
	y2 = std::min(std::max(y2, 0), ((int)cm.c_stop->y - 1) * OPPS);

	stop_loc sl(cm, L);
	intopt::line_touched_ceil(sl, OPPS, x1, y1, x2, y2);
	if (sl.result)
		return 2;
	else
		return 0;
}

struct star_calc {
	ceilmap& CM;
	int idx;
	lua_State *L;
	point start, stop;
	star_calc(ceilmap& cm, lua_State *l, const fpoint& _start, const fpoint& _stop)
		: CM(cm), L(l), start(point(_start)), stop(point(_stop)) {
		idx = 0;
	}
	bool check_neibo(const location& loc) {
		int val = intopt::check(*CM.c_stop, loc);
		return val == 0;
	}
	void push(double x, double y) {
		lua_createtable(L, 0, 2);
		lua_pushnumber(L, x);
		lua_setfield(L, -2, "x");
		lua_pushnumber(L, y);
		lua_setfield(L, -2, "y");
		lua_rawseti(L, -2, ++idx);
	}
	void result(bool ok) {
		lua_pushboolean(L, ok);
		lua_newtable(L);
	}
	void push_point(const point& p) {
		fpoint pos(p);
		push(pos.x, pos.y);
	}
};

static int lfindpath(lua_State * L) {
	ceilmap& cm = check_cm(L, 1);
	double x1 = luaL_checknumber(L, 2);
	double y1 = luaL_checknumber(L, 3);
	double x2 = luaL_checknumber(L, 4);
	double y2 = luaL_checknumber(L, 5);
	lua_Integer maxstep = luaL_optinteger(L, 6, 100);

	fpoint p1(x1, y1), p2(x2, y2);
	star_calc calc(cm, L, p1, p2);
	astar::find_path<star_calc>(calc, p1, p2, maxstep);
	return 2;
}

extern "C" {
	LUAMOD_API
	int luaopen_ceilmap_c(lua_State *L) {
		luaL_checkversion(L);

		luaL_Reg l[] = {
			{"new", lnew},
			{"add", ladd},
			{"del", ldel},
			{"move", lmove},
			{"calc", lcalc},
			{"stop_init", lstop_init},
			{"stop_get", lstop_get},
			{"area_init", larea_init},
			{"area_get", larea_get},
			//{ "export", lslotmap_export},
			{"binary2string", lbinary2string},
			{"string2binary", lstring2binary},
			{"ceil_info", lceil_info},
			{"checkstop", lcheckstop},
			{"findpath", lfindpath},
			{NULL, NULL},
		};
		luaL_newlibtable(L, l);

		lua_createtable(L, 0, 1);
		lua_pushvalue(L, -2);
		lua_setfield(L, -2, "__index");
		lua_pushcfunction(L, lgc);
		lua_setfield(L, -2, "__gc");
		//lua_pushcfunction(L, lslotmap_tostring);
		//lua_setfield(L, -2, "__tostring");

		luaL_setfuncs(L, l, 1);
		return 1;
	}
}
