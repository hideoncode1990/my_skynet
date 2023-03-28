#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#define __STDC_FORMAT_MACROS
#include <inttypes.h>
extern "C" {
#include "skynet.h"
}
#include "toweraoi.h"

#include "seri_buffer.h"

#define TYPE_AOI_MESSAGE_TYPE 111
#define TIMEOUT "10"
using namespace aoi;


struct aoi_reader : public seri::reader {
	aoi_reader(const unsigned char* _buf, size_t _len): seri::reader(_buf, _len) {}
	int read_some() {
		return 0;
	}
	template<typename T, typename ...ARGS>
	int read_some(T& t, ARGS&...args) {
		if (size() < sizeof(T)) {
			return 0;
		}
		read<T>(t);
		return 1 + read_some(args...);
	}
};

struct aoi_object {
	toweraoi * aoi;
	uint32_t master;
	uint32_t count;
};

static void
send_message(toweraoi::aoieventsave& changes, struct skynet_context * ctx, uint32_t master) {
	size_t cnt = changes.size();
	if (cnt == 0) {return;}
	size_t sz = sizeof(int32_t) + cnt * (sizeof(int8_t) + (sizeof(int64_t) + sizeof(int64_t)));
	uint8_t *msg = (uint8_t *)skynet_malloc(sz);
	seri::writer w(msg, sz);
	w.write<int32_t>((int32_t)cnt);
	for (auto iter = changes.begin(); iter != changes.end(); iter++) {
		auto wid = iter->first.first;
		auto oid = iter->first.second;
		auto tp = iter->second;
		w.write<uint8_t, int64_t, int64_t>(tp, wid, oid);
	}

	//for (size_t i = 0; i < sz; i++) {	printf("%d\t", (int)msg[i]);	} printf("\n");
	//skynet_error(ctx, "send_message %d %d %d", master, (int)sz, (int)cnt);
	skynet_send(ctx, 0, master , TYPE_AOI_MESSAGE_TYPE | PTYPE_TAG_DONTCOPY, 0, msg, sz);
}

static void
dispatch_changes(struct skynet_context * ctx, struct aoi_object * inst) {
	auto& changes = inst->aoi->get_changes();
	if (!changes.empty()) {
		send_message(changes, ctx, inst->master);
		changes.clear();
	}
	inst->count = 0;
}

extern "C" struct aoi_object *
toweraoi_create(void) {
	struct aoi_object * inst = (struct aoi_object *)skynet_malloc(sizeof(*inst));
	inst->aoi = NULL;
	return inst;
}

extern "C" void
toweraoi_release(struct aoi_object * inst) {
	if (inst->aoi) {
		delete inst->aoi;
	}
	skynet_free(inst);
}

#define check_ret(ctx,name,obj,r) do {if (r!=0) {skynet_error(ctx, "call "#name " failure! obj(%" PRIi64 ") %d",obj,r);}} while (0);

static void
check_timer(struct skynet_context * ctx, struct aoi_object * inst) {
	if (++inst->count == 1) {
		skynet_command(ctx, "TIMEOUT", TIMEOUT);
	}
}

static int
toweraoi_cb(struct skynet_context * ctx, void *ud, int type, int session, uint32_t source, const void * msg, size_t sz) {
	struct aoi_object * inst = (struct aoi_object *)ud;
	switch (type) {
	case TYPE_AOI_MESSAGE_TYPE: {
		int8_t mid = 0;
		const uint8_t *m = (const uint8_t*)msg;
		try {
			uint32_t x, y, view, otype;
			int64_t obj;

			aoi_reader r(m, sz);
			r.read(mid, obj);
			switch (mid) {
			case 'a': {
				r.read(otype, x, y);
				check_ret(ctx, "a addobject", obj, inst->aoi->addobject(obj, otype, {double(x) / 100, double(y) / 100}));
				break;
			}
			case 'A': {
				r.read(otype, x, y, view);
				check_ret(ctx, "A addwatcher", obj, inst->aoi->addwatcher(obj, otype, {double(x) / 100, double(y) / 100}, view));
				break;
			}
			case 'B': {
				uint32_t wtype;
				r.read(otype, wtype, x, y, view);
				check_ret(ctx, "B addobject", obj, inst->aoi->addobject(obj, otype, {double(x) / 100, double(y) / 100}));
				check_ret(ctx, "B addwatcher", obj, inst->aoi->addwatcher(obj, wtype, {double(x) / 100, double(y) / 100}, view));
				break;
			}
			case 'u': {
				r.read(x, y);
				check_ret(ctx, "u updateobject", obj, inst->aoi->updateobject(obj, {double(x) / 100, double(y) / 100}));
				break;
			}
			case 'U': {
				int cnt = r.read_some(x, y, view);
				if (cnt == 2) {
					check_ret(ctx, "U updatewatcher", obj, inst->aoi->updatewatcher(obj, {double(x) / 100, double(y) / 100}));
				} else if (cnt == 3) {
					check_ret(ctx, "U updatewatcher", obj, inst->aoi->updatewatcher(obj, {double(x) / 100, double(y) / 100}, view));
				} else {
					skynet_error(ctx, "Invalid msg(%d) type(%c) obj(%" PRIi64 ")", (int)sz, mid, obj);
					break;
				}
				break;
			}
			case 'V': {
				int cnt = r.read_some(x, y, view);
				if (cnt == 2) {
					check_ret(ctx, "V updatewatcher", obj, inst->aoi->updatewatcher(obj, {double(x) / 100, double(y) / 100}));
				} else if (cnt == 3) {
					check_ret(ctx, "V updatewatcher", obj, inst->aoi->updatewatcher(obj, {double(x) / 100, double(y) / 100}, view));
				} else {
					skynet_error(ctx, "Invalid msg(%d) type(%c) obj(%" PRIi64 ")", (int)sz, mid, obj);
					break;
				}
				check_ret(ctx, "V updateobject", obj, inst->aoi->updateobject(obj, {double(x) / 100, double(y) / 100}));
				break;
			}
			case 'd': {
				check_ret(ctx, "d removeobject", obj, inst->aoi->removeobject(obj));
				break;
			}
			case 'D': {
				check_ret(ctx, "D removewatcher", obj, inst->aoi->removewatcher(obj));
				break;
			}
			case 'E': {
				check_ret(ctx, "E removeobject", obj, inst->aoi->removeobject(obj));
				check_ret(ctx, "E removewatcher", obj, inst->aoi->removewatcher(obj));
				break;
			}
			default: {
				skynet_error(ctx, "Invalid msg(%d) type %c(%d)", (int)sz, mid, int(mid));
				break;
			}
			}
			inst->aoi->save_changes();
			check_timer(ctx, inst);
		} catch (std::exception& e) {
			skynet_error(ctx, "Invalid msg(%d) %c(%d) %s", (int)sz, mid, int(mid), e.what());
		}
		break;
	}
	case PTYPE_TEXT: {
		const char * m = (const char* )msg;
		if (m[0] == 'K') {
			if (session > 0) {
				const char * data = "CLOSED";
				skynet_send(ctx, 0, source, PTYPE_TEXT, session, (void*)data, 6);
			}
			skynet_error(ctx, "toweraoi EXIT");
			skynet_command(ctx, "EXIT", NULL);
		} else {
			skynet_error(ctx, "Invalid PTYPE_TEXT msg %c", m[0]);
		}
		break;
	}
	case PTYPE_RESPONSE:
		dispatch_changes(ctx, inst);
		break;
	}
	return 0;
}


extern "C" int
toweraoi_init(struct aoi_object * inst, struct skynet_context * ctx, const char * parm) {
	if (parm) {
		int master;
		uint32_t width, height, towerwidth, towerheight;
		int n = sscanf(parm, "%" SCNu32 " %" SCNu32 " %" SCNu32 " %" SCNu32 " %" SCNu32,
		               &master, &width, &height, &towerwidth, &towerheight);
		if (n < 5) {
			skynet_error(ctx, "Invalid gate parm %s", parm);
			return 1;
		}
		if (master <= 0 || width <= 0 || height <= 0 || towerwidth <= 0 || towerheight <= 0) {
			skynet_error(ctx, "Invalid gate parm %s", parm);
			return 1;
		}
		inst->aoi = new toweraoi(width, height, towerwidth, towerheight);
		inst->master = master;
		inst->count = 0;
		skynet_callback(ctx, inst, toweraoi_cb);
		return 0;
	} else {
		return 1;
	}
}
