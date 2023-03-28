/*
email:hongling0@gmail.com
*/
#define LUA_LIB
#include <string.h>
#include <random>

extern "C" {
#include <lualib.h>
#include <lauxlib.h>
}

namespace luard {
class random_device {
public:
	typedef unsigned int result_type;
	explicit	random_device(const std::string& __token = "/dev/urandom") {
		if ((__token != "/dev/urandom" && __token != "/dev/random") || !(_M_file = std::fopen(__token.c_str(), "rb")))
			std::__throw_runtime_error(__N("random_device::random_device(const std::string&)"));
	}
	~random_device() { std::fclose(_M_file); }

	result_type	min() const	{ return std::numeric_limits<result_type>::min(); }
	result_type	max() const	{ return std::numeric_limits<result_type>::max(); }

	double  entropy() const    { return 0.0; }

	result_type operator()() {
		result_type __ret;
		size_t n = std::fread(reinterpret_cast<void*>(&__ret), sizeof(result_type), 1, _M_file);
		if (n != 1) {
			std::fprintf(stderr, "%s\n", strerror(errno));
		}
		return __ret;
	}

	template<typename T>
	bool operator()(T& __ret) {
		return std::fread(reinterpret_cast<void*>(&__ret), sizeof(T), 1, _M_file) == 1;
	}

	bool operator()(void* buf, size_t len) {
		return std::fread(buf, len, 1, _M_file) == 1;
	}
private:
	random_device(const random_device&);
	void operator=(const random_device&);
	FILE* _M_file;
};

template<class _Real, size_t _Bits, class _Gen>
_Real generate_canonical(_Gen& _Gx) {
	const size_t _Digits = static_cast<size_t>(std::numeric_limits<_Real>::digits);
	const size_t _Minbits = _Digits < _Bits ? _Digits : _Bits;

	const _Real _Gxmin = static_cast<_Real>((_Gx.min)());
	const _Real _Gxmax = static_cast<_Real>((_Gx.max)());
	const _Real _Rx = (_Gxmax - _Gxmin) + static_cast<_Real>(1);

	const int _Ceil = static_cast<int>(std::ceil(static_cast<_Real>(_Minbits) / std::log2(_Rx)));
	const int _Kx = _Ceil < 1 ? 1 : _Ceil;

	_Real _Ans = static_cast<_Real>(0);
	_Real _Factor = static_cast<_Real>(1);

	for (int _Idx = 0; _Idx < _Kx; ++_Idx) {
		// add in another set of bits
		_Ans += (static_cast<_Real>(_Gx()) - _Gxmin) * _Factor;
		_Factor *= _Rx;
	}

	return (_Ans / _Factor);
}
}

struct rctx {
	luard::random_device device;
};

static inline rctx* check_rctx(lua_State *L, int idx) {
	rctx* ctx = (rctx*)lua_touserdata(L, idx);
	if (ctx == NULL) {
		luaL_error(L, "expected a rctx value but got a %s @ %d", luaL_typename(L, idx), idx);
	}
	return ctx;
}

template <typename ...ARGS>
static inline void help_read(lua_State *L, int idx, ARGS&...data) {
	rctx* ctx = check_rctx(L, idx);
	if (!ctx->device(data...)) {
		luaL_error(L,"%s", strerror(errno));
	}
}

static int l_double(lua_State *L) {
	rctx* ctx = check_rctx(L, 1);
	auto r = luard::generate_canonical < lua_Number, static_cast<size_t>(-1) > (ctx->device);
	lua_pushnumber(L, r);
	return 1;
}

static int l_integer(lua_State *L) {
	unsigned int ret;
	help_read(L,1,ret);
	lua_pushinteger(L, ret);
	return 1;
}

static int l_bin(lua_State *L) {
	size_t len = luaL_checkinteger(L, 2);
	void *tmp = alloca(len);
	help_read(L,1,tmp,len);
	lua_pushlstring(L, (const char*)tmp, len);
	return 1;
}

static int l_gc(lua_State *L) {
	rctx* ctx = check_rctx(L, 1);
	ctx->~rctx();
	return 0;
}

static int l_new(lua_State *L) {
	const char *fname = luaL_optstring(L, 1, "/dev/urandom");
	FILE *file = fopen(fname, "r");
	if (!file) {
		luaL_error(L, "fopen %s", strerror(errno));
	}
	rctx* ctx = (rctx*)lua_newuserdata(L, sizeof(*ctx));
	new(ctx) rctx;
	lua_newtable(L);
	lua_pushcfunction(L, l_gc);
	lua_setfield(L, -2, "__gc");
	lua_setmetatable(L, -2);
	return 1;
}

extern "C" {
	LUAMOD_API int
	luaopen_random_c(lua_State * L) {
		luaL_checkversion(L);
		luaL_Reg lib[] = {
			{"new", l_new},
			{"double", l_double},
			{"integer", l_integer},
			{"bin", l_bin},
			{NULL, NULL}
		};
		luaL_newlib(L, lib);
		return 1;
	}
}
