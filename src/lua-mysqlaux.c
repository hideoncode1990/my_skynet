#define LUA_LIB

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <lua.h>
#include <lauxlib.h>

#define MAX_BUFF_CHAR 256

static unsigned int num_escape_sql_str(unsigned char *dst, unsigned char *src, size_t size)
{
	unsigned int n =0;
	while (size) {
		/* the highest bit of all the UTF-8 chars
		 * is always 1 */
		if ((*src & 0x80) == 0) {
			switch (*src) {
				case '\0':
				case '\b':
				case '\n':
				case '\r':
				case '\t':
				case 26:  /* \Z */
				case '\\':
				case '\'':
				case '"':
					n++;
					break;
				default:
					break;
			}
		}
		src++;
		size--;
	}
	return n;
}
static unsigned char*
escape_sql_str(unsigned char *dst, unsigned char *src, size_t size)
{

	  while (size) {
		if ((*src & 0x80) == 0) {
			switch (*src) {
				case '\0':
					*dst++ = '\\';
					*dst++ = '0';
					break;

				case '\b':
					*dst++ = '\\';
					*dst++ = 'b';
					break;

				case '\n':
					*dst++ = '\\';
					*dst++ = 'n';
					break;

				case '\r':
					*dst++ = '\\';
					*dst++ = 'r';
					break;

				case '\t':
					*dst++ = '\\';
					*dst++ = 't';
					break;

				case 26:
					*dst++ = '\\';
					*dst++ = 'Z';
					break;

				case '\\':
					*dst++ = '\\';
					*dst++ = '\\';
					break;

				case '\'':
					*dst++ = '\\';
					*dst++ = '\'';
					break;

				case '"':
					*dst++ = '\\';
					*dst++ = '"';
					break;

				default:
					*dst++ = *src;
					break;
			}
		} else {
			*dst++ = *src;
		}
		src++;
		size--;
	} /* while (size) */

	return  dst;
}

static int
escape_sql_str_no_quote(lua_State *L)
{
	size_t len, dlen, escape;
	unsigned char *p;
	unsigned char *src, *dst;
	unsigned char buff[MAX_BUFF_CHAR*2];

	src = (unsigned char *) luaL_checklstring(L, 1, &len);

	if (len == 0) {
		lua_pushvalue(L,1);
		return 1;
	}

	escape = num_escape_sql_str(NULL, src, len);
	if (escape==0){
		lua_pushvalue(L,1);
		return 1;
	}

	dlen = len + escape;
	if (dlen<MAX_BUFF_CHAR){
		p = buff;
	}else{
		p = lua_newuserdata(L, dlen);
	}

	dst = p;

	p = (unsigned char *) escape_sql_str(p, src, len);

	if (p != dst + dlen) {
		return luaL_error(L, "quote sql string error");
	}
	lua_pushlstring(L, (char *) dst, dlen);
	return 1;
}


static int
escape_sql_str_quote(lua_State *L)
{
	size_t len, dlen, escape;
	unsigned char *p;
	unsigned char *src, *dst;

	src = (unsigned char *) luaL_checklstring(L, 1, &len);

	if (len == 0) {
		dst = (unsigned char *) "''";
		dlen = sizeof("''") - 1;
		lua_pushlstring(L, (char *) dst, dlen);
		return 1;
	}

	escape = num_escape_sql_str(NULL, src, len);

	dlen = sizeof("''") - 1 + len + escape;
	p = lua_newuserdata(L, dlen);

	dst = p;

	*p++ = '\'';

	if (escape == 0) {
		memcpy(p, src, len);
		p+=len;
	} else {
		p = (unsigned char *) escape_sql_str(p, src, len);
	}

	*p++ = '\'';

	if (p != dst + dlen) {
		return luaL_error(L, "quote sql string error");
	}

	lua_pushlstring(L, (char *) dst, p - dst);

	return 1;
}

LUAMOD_API int luaopen_mysqlaux_c (lua_State *L) {
	luaL_checkversion(L);
	luaL_Reg lib[] = {
		{"escape",escape_sql_str_no_quote},
		{"escape_quote",escape_sql_str_quote},
		{NULL, NULL}
	};
	luaL_newlib(L, lib);
	return 1;
}
