CC ?= gcc

CFLAGS = -g -O2 -Wall -I$(LUA_INC) $(MYCFLAGS)
SHARED := -fPIC --shared


#skynet
SKYNET :=skynet

# lua
LUA_STATICLIB := $(SKYNET)/3rd/lua/liblua.a
LUA_LIB ?= $(LUA_STATICLIB)
LUA_INC ?= $(SKYNET)/3rd/lua

CSERVICE_PATH ?= cservice

all: $(CSERVICE_PATH)/logger.so

$(CSERVICE_PATH)/logger.so: src/srvice_logger.c
	$$(CC) $$(CFLAGS) $$(SHARED) $$< -o $$@ -I$(SKYNET)/skynet-src
