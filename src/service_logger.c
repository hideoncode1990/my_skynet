#include "skynet.h"

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include "skynet_env.h"
#include <sys/stat.h>
#include "skynet_timer.h"
#include "skynet_server.h"

struct logger {
	int stdout;
	FILE * handle;
	char * filename;
	int close;
	int loggersize;
	int filesize;
};

static int
optint(const char *key, int opt) {
	const char * str = skynet_getenv(key);
	if (str == NULL) {
		char tmp[20];
		sprintf(tmp, "%d", opt);
		skynet_setenv(key, tmp);
		return opt;
	}
	return strtol(str, NULL, 10);
}

struct logger *
logger_create(void) {
	struct logger * inst = skynet_malloc(sizeof(*inst));
	inst->handle = NULL;
	inst->close = 0;
	inst->filename = NULL;
	inst->loggersize = 0;
	inst->filesize = 0;
	inst->stdout = 1;
	return inst;
}

void
logger_release(struct logger * inst) {
	if (inst->close) {
		fclose(inst->handle);
	}
	skynet_free(inst->filename);
	skynet_free(inst);
}

static void getnewname(const char *parm, char *nparm) {
	time_t rawtime;
	struct tm * timeinfo;
	int sz = 256;
	char buffer[sz];
	memset(buffer, 0, sz);
	time(&rawtime);
	timeinfo = localtime(&rawtime);
	strftime(buffer, sizeof(buffer), "%Y%m%d%H%M%S", timeinfo);
	sprintf(nparm, "%s-%s", parm, buffer);
}

static void checkfilesize(struct logger *inst) {
	if (inst->filename && inst->filesize >= inst->loggersize) {
		int sz = 256;
		char newname[sz];
		memset(newname, 0, sz);
		getnewname(inst->filename, newname);
		rename(inst->filename, newname);
		fclose(inst->handle);
		inst->handle = fopen(inst->filename, "a");
		inst->filesize = 0;
	}
}

static int
logger_cb(struct skynet_context * context, void *ud, int type, int session, uint32_t source, const void * msg, size_t sz) {
	struct logger * inst = ud;
	switch (type) {
	case PTYPE_SYSTEM:
		if (inst->filename) {
			inst->handle = freopen(inst->filename, "a", inst->handle);
		}
		break;
	case PTYPE_RESERVED_LUA:
		skynet_command(context,"EXIT","");
		break;
	case PTYPE_TEXT:
		checkfilesize(inst);
		double now = skynet_starttime() + (double)skynet_now() / 100;
		int len = fprintf(inst->handle, "[:%08x %.02f] ", source, now);
		if(inst->filename){
			fwrite(msg, sz , 1, inst->handle);
			fprintf(inst->handle, "\n");
			fflush(inst->handle);
			inst->filesize += sz + len + 1;// todo io error; fprintf fwrite
		}
		if(inst->stdout){
			fprintf(stdout, "[:%08x %.02f] ", source, now);
			fwrite(msg, sz , 1, stdout);
			fprintf(stdout, "\n");
		}
		break;
	}
	return 0;
}

static int getfilesize(FILE *fd) {
	struct stat buf;
	int fds = fileno(fd);
	fstat(fds, &buf);
	return buf.st_size;
}

int
logger_init(struct logger * inst, struct skynet_context *ctx, const char * parm) {
	if (parm) {
		inst->handle = fopen(parm, "a");
		if (inst->handle == NULL) {
			return 1;
		}
		inst->loggersize = optint("loggersize", 1024 * 1024);
		inst->filesize = getfilesize(inst->handle);
		inst->filename = skynet_malloc(strlen(parm) + 1);
		strcpy(inst->filename, parm);
		inst->close = 1;
		const char* daemon= skynet_getenv("daemon");
		if(daemon){
			inst->stdout=0;
		}
		skynet_callback(ctx, inst, logger_cb);
#ifdef _DEBUG_DEFINE
#define WARN_MESSAGE(EXPR) "\x1B[31m" #EXPR "\x1B[0m"
#define MESSAGE1 WARN_MESSAGE(RUNNING IN DEBUG VERSION)
#define MESSAGE2 WARN_MESSAGE(RELEASE VERSION need compile with make cleanall && make release)
		skynet_send(ctx, 0, skynet_context_handle(ctx), PTYPE_TEXT, 0, MESSAGE1, sizeof(MESSAGE1));
		skynet_send(ctx, 0, skynet_context_handle(ctx), PTYPE_TEXT, 0, MESSAGE2, sizeof(MESSAGE2));
#endif
		return 0;
	}
	return 1;
}
