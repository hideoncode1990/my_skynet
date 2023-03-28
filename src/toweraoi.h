#ifndef __toweraoi_h
#define __toweraoi_h
#include <assert.h>
#include <cmath>
#include <stdint.h>
#include <stdlib.h>
#include <unordered_set>
#include <unordered_map>
#include <vector>

namespace aoi {

template<typename T>
T** malloc_array2d(int row, int col) {
	T **arr = (T **)malloc(sizeof(T*) * row + sizeof(T) * row * col);
	T *head = (T*)(((char*)arr) + row * sizeof(T*));
	while (row--)
		arr[row] = (T*)((char*)head + row * col * sizeof(T));
	return arr;
}

struct position {
	double x;
	double y;
	position(double x = 0, double y = 0) : x(x), y(y) {}
	position(const position& pos) : x(pos.x), y(pos.y) {}
};

struct location {
	uint32_t x;
	uint32_t y;
	location(uint32_t x, uint32_t y) : x(x), y(y) {}
};

struct region {
	location startpos;
	location endpos;
	region(uint32_t startx, uint32_t starty, uint32_t endx, uint32_t endy) : startpos(startx, starty), endpos(endx, endy) {}
	region() : startpos(0, 0), endpos(0, 0) {}
};

struct object {
	int64_t id;
	uint8_t type;
	position pos;
	object(int64_t _id, uint8_t _type, const position& _pos) : id(_id), type(_type), pos(_pos) {}
	object() {}
};

struct watcher {
	int64_t id;
	uint32_t wtype;
	position pos;
	uint32_t range;
	watcher(int64_t _id, uint32_t _wtype, const position& _pos, uint32_t _range) : id(_id), wtype(_wtype), pos(_pos), range(_range) {}
	watcher() {}
};

typedef std::unordered_set<object*> objectset;
typedef std::unordered_map<int64_t, object> objectmap;
typedef std::unordered_set<watcher*> watcherset;
typedef std::unordered_map<int64_t, watcher> watchermap;

class tower {
public:
	tower(uint32_t id, uint32_t x, uint32_t y) : m_id(id), m_pos(x, y) {}
	tower() = delete;
	tower(const tower&) = delete;
	~tower() = default;

	uint32_t getid() { return m_id; }

	bool add(object* obj) {
		return m_objset.insert(obj).second;
	}

	bool remove(object* obj) {
		return m_objset.erase(obj) > 0;
	}

	bool addwatcher(watcher* obj) {
		return m_watcherset.insert(obj).second;
	}

	bool removewatcher(watcher* obj) {
		return m_watcherset.erase(obj) > 0;
	}

	const objectset& getobjects() { return m_objset; }
	const watcherset& getwatchers() { return m_watcherset; }
	location getpos() { return m_pos; }
private:
	objectset m_objset;
	watcherset m_watcherset;
	const uint32_t m_id;
	const location m_pos;
};

struct hash_pairs {
	template<typename T1, typename T2>
	size_t operator()(const std::pair<T1, T2>& x) const {
		std::hash<T1> h1;
		std::hash<T2> h2;
		return h1(x.first)^h2(x.second);
	}
};

#define ERR_OK 0
#define ERR_POS 1
#define ERR_OBJ 2

class toweraoi {
public:
	typedef std::pair < int64_t, uint64_t> aoipair;
	typedef std::vector<aoipair> aoipairlist;
	typedef std::unordered_map<aoipair, uint8_t, hash_pairs> aoievents;
	typedef std::vector<std::pair<aoipair, uint8_t>> aoieventsave;

	toweraoi(uint32_t width, uint32_t height, uint32_t towerwidth, uint32_t towerheight) :
		m_width(width), m_height(height),
		m_towerwidth(towerwidth), m_towerheight(towerheight) {

		m_towerx = (uint32_t)ceil((double)width / towerwidth);
		m_towery = (uint32_t)ceil((double)height / towerheight);

		m_towers = malloc_array2d<tower>(m_towerx, m_towery);

		for (uint32_t x = 0; x < m_towerx; x++) {
			for (uint32_t y = 0; y < m_towery; y++) {
				new(&m_towers[x][y])tower(x * m_towery + y, x, y);
			}
		}
	}
	toweraoi() = delete;
	toweraoi(const toweraoi&) = delete;
	~toweraoi() {
		for (uint32_t x = 0; x < m_towerx; x++) {
			for (uint32_t y = 0; y < m_towery; y++) {
				m_towers[x][y].~tower();
			}
		}
		free(m_towers);
	}

	void dispatch(const object& obj, const watcherset& set, uint8_t flag) {
		for (auto it = set.begin(); it != set.end(); it++) {
			if ((*it)->wtype & obj.type) {
				auto ret = changes.insert(std::make_pair(std::make_pair((*it)->id, obj.id), flag));
				if (!ret.second) {
					if (ret.first->second != flag) {
						changes.erase(ret.first);
					}
				}
			}
		}
	}
	void dispatch(const watcher& obj, const objectset& set, uint8_t flag) {
		for (auto it = set.begin(); it != set.end(); it++) {
			if ((*it)->type & obj.wtype) {
				auto ret = changes.insert(std::make_pair(std::make_pair(obj.id, (*it)->id), flag));
				if (!ret.second) {
					if (ret.first->second != flag) {
						changes.erase(ret.first);
					}
				}
			}
		}
	}

	int addobject(int64_t id, uint8_t type, const position& pos) {
		if (!checkpos(pos)) return ERR_POS;
		if (!m_objects.insert(std::make_pair(id, object(id, type, pos))).second) {return ERR_OBJ;}
		auto& obj = m_objects.find(id)->second;
		auto towerpos = translatepos(pos);
		bool rt = m_towers[towerpos.x][towerpos.y].add(&obj);
		assert(rt);
		dispatch(obj, m_towers[towerpos.x][towerpos.y].getwatchers(), 1);
		return ERR_OK;
	}

	int removeobject(int64_t id) {
		auto iter = m_objects.find(id);
		if (iter == m_objects.end()) {return ERR_OBJ;}
		auto& obj = iter->second;
		location towerpos = translatepos(obj.pos);
		bool rt = m_towers[towerpos.x][towerpos.y].remove(&obj);
		assert(rt);
		dispatch(obj, m_towers[towerpos.x][towerpos.y].getwatchers(), 2);
		m_objects.erase(iter);
		return ERR_OK;
	}

	int updateobject(int64_t id, const position& newpos) {
		if (!checkpos(newpos)) {return ERR_POS;}
		auto iter = m_objects.find(id);
		if (iter == m_objects.end()) {return ERR_OBJ;}
		auto& obj = iter->second;
		location oldtower = translatepos(obj.pos);
		location newtower = translatepos(newpos);
		if (oldtower.x != newtower.x || oldtower.y != newtower.y) {
			m_towers[oldtower.x][oldtower.y].remove(&obj);
			m_towers[newtower.x][newtower.y].add(&obj);
			dispatch(obj, m_towers[newtower.x][newtower.y].getwatchers(), 1);
			dispatch(obj, m_towers[oldtower.x][oldtower.y].getwatchers(), 2);
		}
		obj.pos = newpos;
		return ERR_OK;
	}

	int addwatcher(int64_t w, uint32_t wtype, const position& pos, uint32_t range) {
		if (!checkpos(pos) || !checkrange(range)) { return ERR_POS;}
		if (!m_watchers.insert(std::make_pair<uint64_t, watcher>(w, {w, wtype, pos, range})).second) {return ERR_OBJ;}

		auto& wobj = m_watchers.find(w)->second;
		location towerpos = translatepos(pos);
		region region = getregion(towerpos, range);
		for (uint32_t x = region.startpos.x; x < region.endpos.x; x++) {
			for (uint32_t y = region.startpos.y; y < region.endpos.y; y++) {
				m_towers[x][y].addwatcher(&wobj);
				dispatch(wobj, m_towers[x][y].getobjects(), 1);
			}
		}
		return ERR_OK;
	}

	int removewatcher(int64_t w) {
		auto iter = m_watchers.find(w);
		if (iter == m_watchers.end()) {return ERR_OBJ;}
		auto& wobj = iter->second;

		location towerpos = translatepos(wobj.pos);
		region region = getregion(towerpos, wobj.range);
		for (uint32_t x = region.startpos.x; x < region.endpos.x; x++) {
			for (uint32_t y = region.startpos.y; y < region.endpos.y; y++) {
				m_towers[x][y].removewatcher(&wobj);
				dispatch(wobj, m_towers[x][y].getobjects(), 2);
			}
		}
		m_watchers.erase(iter);
		return ERR_OK;
	}

	int inner_updatewatcher(watcher &wobj, const position& newpos, uint32_t newrange) {
		auto oldtower = translatepos(wobj.pos);
		auto newtower = translatepos(newpos);
		if (oldtower.x == newtower.x && oldtower.y == newtower.y && wobj.range == newrange) {return ERR_OK;}
//key: 0->addedtowers 1->removedtowers 2->unchangetowers
		std::vector<tower*> towers[3];
		getchangedtowers(towers, oldtower, newtower, wobj.range, newrange);
		for (auto iter = towers[1].begin(); iter != towers[1].end(); ++iter) {
			auto& c = *iter;
			c->removewatcher(&wobj);
			dispatch(wobj, c->getobjects(), 2);
		}
		for (auto iter = towers[0].begin(); iter != towers[0].end(); ++iter) {
			auto& c = *iter;
			c->addwatcher(&wobj);
			dispatch(wobj, c->getobjects(), 1);
		}
		wobj.pos = newpos;
		wobj.range = newrange;
		return ERR_OK;
	}

	bool updatewatcher(int64_t w, const position& newpos) {
		if (!checkpos(newpos)) {return ERR_POS;}
		auto iter = m_watchers.find(w);
		if (iter == m_watchers.end()) {return ERR_OBJ;}
		auto& wobj = iter->second;
		return inner_updatewatcher(wobj, newpos, wobj.range);
	}

	bool updatewatcher(int64_t w, const position& newpos, uint32_t newrange) {
		if (!checkpos(newpos) || !checkrange(newrange)) {return ERR_POS;}
		auto iter = m_watchers.find(w);
		if (iter == m_watchers.end()) {return ERR_OBJ;}
		auto& wobj = iter->second;
		return inner_updatewatcher(wobj, newpos, newrange);
	}
	aoieventsave& get_changes() {
		return eventssave;
	}
	void save_changes() {
		for (auto iter = changes.begin(); iter != changes.end(); iter++) {
			//eventssave.push_back(std::make_pair(iter->first, iter->second));
			eventssave.push_back(*iter);
		}
		changes.clear();
	}
private:
	void getchangedtowers(std::vector<tower*> towers[3], const location& oldpos, const location& newpos, uint32_t oldrange, uint32_t newrange) {
		region oldregion = getregion(oldpos, oldrange);
		region newregion = getregion(newpos, newrange);
		//key: 0->addedtowers 1->removedtowers 2->unchangetowers
		for (uint32_t x = oldregion.startpos.x; x < oldregion.endpos.x; x++) {
			for (uint32_t y = oldregion.startpos.y; y < oldregion.endpos.y; y++) {
				if (isinrect(location(x, y), newregion.startpos, newregion.endpos)) {
					towers[2].push_back(&m_towers[x][y]);
				} else {
					towers[1].push_back(&m_towers[x][y]);
				}
			}
		}
		for (uint32_t x = newregion.startpos.x; x < newregion.endpos.x; x++) {
			for (uint32_t y = newregion.startpos.y; y < newregion.endpos.y; y++) {
				if (!isinrect(location(x, y), oldregion.startpos, oldregion.endpos)) {
					towers[0].push_back(&m_towers[x][y]);
				}
			}
		}
	}

	bool checkpos(const position& pos) const {
		if (pos.x < 0 || pos.y < 0 || pos.x >= m_width || pos.y >= m_height) {
			return false;
		}
		return true;
	}

	bool checkrange(uint32_t range) const {
		if (range <= 0 || range > range_limit) {
			return false;
		}
		return true;
	}

	bool isinrect(const location& pos, const location& startpos, const location& endpos) const {
		return pos.x >= startpos.x && pos.x < endpos.x && pos.y >= startpos.y && pos.y < endpos.y;
	}

	location translatepos(const position& pos) const {
		return location((uint32_t)floor(pos.x / m_towerwidth), (uint32_t)floor(pos.y / m_towerheight));
	}

	region getregion(const location& pos, uint32_t range) {
		region region;
		region.startpos.x = pos.x < range ? 0 : (pos.x - range);
		region.endpos.x = std::min(pos.x + range + 1, m_towerx);
		region.startpos.y = pos.y < range ? 0 : (pos.y - range);
		region.endpos.y = std::min(pos.y + range + 1, m_towery);
		return region;
	}
private:
	const uint32_t m_width;
	const uint32_t m_height;
	const uint32_t m_towerwidth;
	const uint32_t m_towerheight;
	uint32_t m_towerx;
	uint32_t m_towery;
	tower **m_towers;
	objectmap m_objects;
	watchermap m_watchers;
	static const uint32_t range_limit = 5;
	aoievents changes;
	aoieventsave eventssave;
};
}

#endif
