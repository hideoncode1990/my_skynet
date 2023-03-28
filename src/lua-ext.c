/*
email:hongling0@gmail.com
*/
#define LUA_LIB

#include <inttypes.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>
#include <time.h>
#include <unistd.h>
#include <libgen.h>
#include <sys/stat.h>
#include <errno.h>

#include <lualib.h>
#include <lauxlib.h>

static int lnew_table(lua_State *L) {
	lua_Integer narray = luaL_optinteger(L, 1, 0);
	lua_Integer nrec = luaL_optinteger(L, 2, 0);
	lua_createtable(L, narray, nrec);
	return 1;
}

static inline void
split_string(const char *source, size_t len, const char *sp, void (*callback)(void* ctx, const char* s, size_t len), void* ctx) {
	if (len > 0) {
		if (!(*sp)) {
			callback(ctx, source, len);
		} else {
			const char *src = source;
			const char *end = strstr(src, sp);
			while (end && *end) {
				callback(ctx, src, end - src);
				src = ++end;
				end = strstr(src, sp);
			}
			callback(ctx, src, len - (src - source));
		}
	}
}

struct split_string_ctx {
	lua_State* L;
	int index;
	int skip;
};

static inline void
split_string_callback(void* context, const char* src, size_t len) {
	struct split_string_ctx* ctx = (struct split_string_ctx*)context;
	if(len==0&&ctx->skip){
		return;
	}
	lua_pushlstring(ctx->L, src, len);
	lua_rawseti(ctx->L, -2, ++ctx->index);
}

static int
lsplit_string(lua_State *L) {
	size_t len;
	const char* src = luaL_checklstring(L, 1, &len);
	const char* sp = luaL_optstring(L, 2, " ");
	int skip = luaL_optinteger(L, 3, 0);
	lua_newtable(L);
	struct split_string_ctx ctx = {L, 0, skip};
	split_string(src, len, sp, split_string_callback, &ctx);
	return 1;
}

static inline void
split_unpackstring_callback(void* context, const char* src, size_t len) {
	struct split_string_ctx* ctx = (struct split_string_ctx*)context;
	if(len==0&&ctx->skip){
		return;
	}
	lua_pushlstring(ctx->L, src, len);
	++ctx->index;
}

static int
lsplit_string_row(lua_State *L) {
	size_t len;
	const char* src = luaL_checklstring(L, 1, &len);
	const char* sp = luaL_optstring(L, 2, " ");
	int skip = luaL_optinteger(L, 3, 0);
	struct split_string_ctx ctx = {L, 0, skip};
	split_string(src, len, sp, split_unpackstring_callback, &ctx);
	return ctx.index;
}

static int
create_parent_dir(const char *name, size_t sz) {
	if (access(name, 0) != 0) {
		char tmp[sz];
		strcpy(tmp, name);
		char *parent = dirname(tmp);
		if (create_parent_dir(parent, strlen(parent)) == 0) {
			return mkdir(name, 0755);
		}
		return -1;
	} else {
		return 0;
	}
}

static int
lmkdir(lua_State *L) {
	size_t sz;
	const char *name = luaL_checklstring(L, 1, &sz);
	char tmp[sz];
	strcpy(tmp, name);
	char *parent = dirname(tmp);
	int r = create_parent_dir(parent, strlen(parent));
	switch (r) {
	case -1: {
		luaL_error(L, "%s", strerror(errno));
		break;
	}
	case 0: {
		break;
	}
	default: {
		luaL_error(L, "unknow err %d", r);
		break;
	}
	}
	return 0;
}

static inline void
trim_left(const char * in_buff,size_t in_len,const  char** out_buff,size_t *out_len){
	size_t start=0;
	for(;start<in_len;start++){
		if(!isspace(in_buff[start]))
			break;
	}
	*out_buff=in_buff+start;
	*out_len=in_len-start;
}

static inline void
trim_right(const  char * in_buff,size_t in_len,size_t *out_len){
	if(in_len>0){
		size_t end=in_len-1;
		while(end>0){
			if(isspace(in_buff[end]))
				--end;
			else
				break;
		}
		if(end==0&&isspace(in_buff[0]))
			*out_len=0;
		else
			*out_len=end+1;
	}else{
		*out_len=0;
	}
}

static inline void
ignore_multi_space(const char * in_buff,size_t in_len,char * out_buff,size_t* out_len){
	size_t idx=0;
	int is_space=0;
	for(size_t i=0;i<in_len;i++){
		if(isspace(in_buff[i])){
			if(is_space==0){
				is_space=1;
			}else{
				continue;
			}
		}else{
			is_space=0;
		}
		out_buff[idx++]=in_buff[i];
	}
	*out_len=idx;
}

static int
name_trim(lua_State *L){
	size_t sz;
	const char *str = luaL_checklstring(L, 1, &sz);
	char buff[sz+1];
	memcpy(buff,str,sz);
	buff[sz]='\0';

	const char *out_str;
	size_t olen;
	trim_left(str,sz,&out_str,&olen);
	trim_right(out_str,olen,&olen);
	ignore_multi_space(out_str,olen,buff,&olen);
	lua_pushlstring(L,buff,olen);
	return 1;
}

LUAMOD_API int
luaopen_ext_c(lua_State * L) {
	luaL_checkversion(L);
	struct luaL_Reg lib[] = {
		{"newtable", lnew_table},
		{"split_string", lsplit_string},
		{"splitrow_string", lsplit_string_row},
		{"mkdir", lmkdir},
		{"name_trim", name_trim},
		{NULL, NULL}
	};
	luaL_newlib(L, lib);
	return 1;
}
