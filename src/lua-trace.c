/*
** $Id: ldblib.c,v 1.151 2015/11/23 11:29:43 roberto Exp $
** Interface from Lua to its debug API
** See Copyright Notice in lua.h
*/

#define ltrace_c
#define LUA_LIB

#include "lprefix.h"


#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lua.h"

#include "lauxlib.h"
#include "lualib.h"

#define LEVELS1	10	/* size of the first part of the stack */
#define LEVELS2	11	/* size of the second part of the stack */

static lua_State *getthread (lua_State *L, int *arg) {
	if (lua_isthread(L, 1)) {
		*arg = 1;
		return lua_tothread(L, 1);
	} else {
		*arg = 0;
		return L;  /* function will operate over current thread */
	}
}

static int lastlevel (lua_State *L) {
	lua_Debug ar;
	int li = 1, le = 1;
	/* find an upper bound */
	while (lua_getstack(L, le, &ar)) { li = le; le *= 2; }
	/* do a binary search */
	while (li < le) {
		int m = (li + le) / 2;
		if (lua_getstack(L, m, &ar)) li = m + 1;
		else le = m;
	}
	return le - 1;
}
static int findfield (lua_State *L, int objidx, int level) {
	if (level == 0 || !lua_istable(L, -1))
		return 0;  /* not found */
	lua_pushnil(L);  /* start 'next' loop */
	while (lua_next(L, -2)) {  /* for each pair in table */
		if (lua_type(L, -2) == LUA_TSTRING) {  /* ignore non-string keys */
			if (lua_rawequal(L, objidx, -1)) {  /* found object? */
				lua_pop(L, 1);  /* remove value (but keep name) */
				return 1;
			} else if (findfield(L, objidx, level - 1)) { /* try recursively */
				lua_remove(L, -2);  /* remove table (but keep name) */
				lua_pushliteral(L, ".");
				lua_insert(L, -2);  /* place '.' between the two names */
				lua_concat(L, 3);
				return 1;
			}
		}
		lua_pop(L, 1);  /* remove value */
	}
	return 0;  /* not found */
}

static int pushglobalfuncname (lua_State *L, lua_Debug *ar, int in_stack) {
	int top = lua_gettop(L);
	if (in_stack) {
		lua_getinfo(L, "f", ar);  /* push function */
	} else {
		lua_pushvalue(L,1);  /*	check_function */
	}
	lua_getfield(L, LUA_REGISTRYINDEX, LUA_LOADED_TABLE);
	if (findfield(L, top + 1, 2)) {
		const char *name = lua_tostring(L, -1);
		if (strncmp(name, "_G.", 3) == 0) {  /* name start with '_G.'? */
			lua_pushstring(L, name + 3);  /* push name without prefix */
			lua_remove(L, -2);  /* remove original name */
		}
		lua_copy(L, -1, top + 1);  /* move name to proper place */
		lua_pop(L, 2);  /* remove pushed values */
		return 1;
	} else {
		lua_settop(L, top);  /* remove function and global table */
		return 0;
	}
}

static void pushfuncname (lua_State *L, lua_Debug *ar, int in_stack) {
	if (pushglobalfuncname(L, ar, in_stack)) { /* try first a global name */
		lua_pushfstring(L, "function '%s'", lua_tostring(L, -1));
		lua_remove(L, -2);  /* remove name */
	} else if (*ar->namewhat != '\0') /* is there a name from code? */
		lua_pushfstring(L, "%s '%s'", ar->namewhat, ar->name);  /* use it */
	else if (*ar->what == 'm')  /* main? */
		lua_pushliteral(L, "main chunk");
	else if (*ar->what != 'C')  /* for Lua functions, use <file:line> */
		lua_pushfstring(L, "function <%s:%d>", ar->short_src, ar->linedefined);
	else  /* nothing left... */
		lua_pushliteral(L, "?");
}

static int control_char(lua_State *L) {
	const char * byte = luaL_checkstring(L, 1);
	switch(*byte){
		case '\n':
		case '\t':{
			lua_pushlstring(L,byte,1);
			break;
		}
		default:{
			char tmp[5];
			sprintf(tmp,"\\%02X",(int)(*byte));
			lua_pushstring(L,tmp);
			break;
		}
	}
	return 1;
}

static int check_string(lua_State *L) {
	luaL_checkany(L, 1);
	lua_pushvalue(L, lua_upvalueindex(1));	//string.gsub
	luaL_tolstring(L, 1, NULL);
	lua_pushliteral(L, "([%c])");
	lua_pushvalue(L, lua_upvalueindex(2));
	lua_call(L, 3, 1);
	return 1;
}

static int check_function(lua_State *L) {
	lua_Debug ar;
	luaL_checktype(L, 1, LUA_TFUNCTION);
	lua_pushvalue(L, 1);
	lua_getinfo(L, ">Sn", &ar);
	lua_pushvalue(L, 1);
	pushfuncname(L, &ar, 0);
	// const char *value=luaL_tolstring(L, 1, NULL);
	// lua_pushfstring(L,"%s %s:%d",value,ar.short_src,ar.linedefined);
	return 1;
}

static int check_local(lua_State *L) {
	if (lua_type(L, 1) == LUA_TFUNCTION) {
		return check_function(L);
	} else {
		return check_string(L);
	}
}

static void my_traceback (lua_State *L, lua_State *L1,
                          const char *msg, int level) {
	lua_Debug ar;
	int top = lua_gettop(L);
	int last = lastlevel(L1);
	int n1 = (last - level > LEVELS1 + LEVELS2) ? LEVELS1 : -1;
	if (msg)
		lua_pushfstring(L, "%s\n", msg);
	luaL_checkstack(L, 10, NULL);
	lua_pushliteral(L, "stack traceback:");
	while (lua_getstack(L1, level++, &ar)) {
		if (n1-- == 0) {  /* too many levels? */
			luaL_checkstack(L, 1, NULL);
			lua_pushliteral(L, "\n...");  /* add a '...' */
			level = last - LEVELS2 + 1;  /* and skip to last ones */
		} else {
			luaL_checkstack(L, 4, NULL);
			lua_getinfo(L1, "Slnt", &ar);
			lua_pushfstring(L, "\n\t%d %s:", level, ar.short_src);
			if (ar.currentline > 0)
				lua_pushfstring(L, "%d:", ar.currentline);
			lua_pushliteral(L, " in ");
			pushfuncname(L, &ar, 1);
			if (*ar.what != 'C') {
				int nvar = 1;
				for (;;) {
					luaL_checkstack(L1, 1, NULL);
					luaL_checkstack(L, 3, NULL);
					const char *name = lua_getlocal(L1, &ar, nvar);
					if (name == NULL)
						break;
					lua_xmove(L1, L, 1);
					lua_pushfstring(L, "\n\t\t%d (%s) %s ", nvar++, luaL_typename(L, -1), name);
					lua_pushvalue(L, lua_upvalueindex(1));
					lua_rotate(L, -3, -1);
					lua_call(L, 1, 1);
				}
			}
			if (ar.istailcall)
				lua_pushliteral(L, "\n(...tail calls...)");
			lua_concat(L, lua_gettop(L) - top);
		}
	}
	lua_concat(L, lua_gettop(L) - top);
}


static int traceback (lua_State *L) {
	int arg;
	lua_State *L1 = getthread(L, &arg);
	const char *msg = lua_tostring(L, arg + 1);
	if (msg == NULL && !lua_isnoneornil(L, arg + 1))  /* non-string 'msg'? */
		lua_pushvalue(L, arg + 1);  /* return it untouched */
	else {
		int level = (int)luaL_optinteger(L, arg + 2, (L == L1) ? 1 : 0);
		my_traceback(L, L1, msg, level);
	}
	return 1;
}

LUAMOD_API int luaopen_trace_c (lua_State *L) {
	lua_getglobal(L, "string");
	lua_getfield(L, -1, "gsub");
	lua_remove(L, -2);
	lua_pushcfunction(L, control_char);
	lua_pushcclosure(L, check_local, 2);
	lua_pushcclosure(L, traceback, 1);
	return 1;
}
