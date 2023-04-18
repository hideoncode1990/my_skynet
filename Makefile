CC = gcc

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
	cd ./$(SKYNET)&& make linux

$(CSERVICE_PATH)/logger.so: src/service_logger.c
	$(CC) $(CFLAGS) $(SHARED) $< -o $@ -I$(SKYNET)/skynet-src

#$(SKYNET):
# cd ($SKYNET)&& make linux