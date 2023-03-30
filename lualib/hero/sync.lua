local skynet = require "skynet"
local client = require "client.mods"
local event = require "role.event"
local cfgproxy = require "cfg.proxy"
local award = require "role.award"
local task = require "task"
local uaward = require "util.award"
local utime = require "util.time"
local flowlog = require "flowlog"

local cache = require("mongo.role")("herosync")
local schema = require "mongo.schema"
cache.schema(schema.OBJ {
    build = schema.ORI,
    open = schema.ORI,
    buy = schema.ORI,
    synctbl = schema.MAPF("pos", schema.ORI)
})

local BASIC, HEROSYNC_BUY, HEROSYNC_LATTICE, HERO_LEVEL
skynet.init(function()
    BASIC, HEROSYNC_BUY, HEROSYNC_LATTICE, HERO_LEVEL =
        cfgproxy("basic", "herosync_buy", "herosync_lattice", "hero_level")
end)

local _M = {}

local NM<const> = "herosync"
local CACHE

local function defaultsz(self, C)
    if not C then C = cache.get(self) end
    local basic = BASIC.herosync_base_size
    if C.build then basic = basic + BASIC.herobest_count end
    return basic
end

local function tablemax(self, C)
    if not C then C = cache.get(self) end
    return (C.open or 0) + defaultsz(self, C)
end

local function sendall(self)
    local C = cache.get(self)
    client.enter(self, NM, "herosync_list", {
        list = CACHE.pos2d,
        size = tablemax(self),
        buy = C.buy,
        build = C.build
    })
end

local function remove_obj(self, uuid2d, pos2d, uuid, log)
    local d = uuid2d[uuid]
    if d then
        local pos = d.pos

        local dd
        if log then dd = {pos = pos, optime = utime.time()} end

        pos2d[pos], uuid2d[uuid] = dd, nil
        cache.dirty(self)
        event.occur("EV_HERO_SYNCCHG", self, uuid)
        return true, dd
    else
        return false
    end
end

local function checkadd(dd)
    if dd then
        if dd.uuid then
            return false, 4
        elseif dd.optime then
            if dd.optime + BASIC.herosync_reuse_time > utime.time() then
                return false, 5
            end
        end
    end
    return true
end

function _M.cleancd(self, pos)
    local pos2d = CACHE.pos2d
    local dd = pos2d[pos]
    if not dd then return false, 1 end
    if dd.uuid then return false, 2 end

    local optime = dd.optime
    if not optime then return false, 1 end
    local cd = dd.optime + BASIC.herosync_reuse_time - utime.time()
    if cd <= 0 then return false, 1 end
    local n = math.ceil(cd / BASIC.herosync_clean_time)
    local cost_result = uaward().append_one(BASIC.herosync_clean).multi(n)
                            .result

    local ok, err = award.del(self, {flag = "herosync", arg1 = cd}, cost_result)
    if not ok then return false, err end

    pos2d[pos] = nil
    cache.dirty(self)
    return true
end

function _M.build(self)
    return cache.get(self).build
end

function _M.build_change(self, level)
    local C = cache.get(self)
    C.build = assert(level)
    cache.dirty(self)
end

function _M.build_levelup(self, level)
    local C = cache.get(self)
    local build = C.build
    local before = build
    if not build then return false, 1 end

    if level ~= build + 1 then return false, 2 end
    assert(level > BASIC.herobest_build_level)

    local cfg = HERO_LEVEL[build]
    if not cfg then return false, 3 end -- max level

    local ok, err = award.del(self, {flag = "build_levelup", arg1 = level},
        cfg.consume)
    if not ok then return false, err end

    C.build = level
    cache.dirty(self)
    _M.herobest_change(self)
    flowlog.role(self, NM, {flag = NM, before = before, now = level})
    return true
end

function _M.add_anyway(self, uuid)
    for pos = 1, tablemax(self, cache.get(self)) do
        if _M.add(self, uuid, pos) then break end
    end
end

function _M.add(self, uuid, pos)
    local C = cache.get(self)
    local maxpos = tablemax(self, C)

    if pos < 0 or pos > maxpos then return false, 2 end

    local uuid2d, pos2d = CACHE.uuid2d, CACHE.pos2d
    if uuid2d[uuid] then return false, 3 end

    local dd = pos2d[pos]
    local ok, e = checkadd(dd)
    if not ok then return false, e end

    assert(not uuid2d[uuid])
    local d = {uuid = uuid, pos = pos}
    uuid2d[uuid], pos2d[pos] = d, d
    cache.dirty(self)
    event.occur("EV_HERO_SYNCCHG", self, uuid)
    return true
end

function _M.remove(self, uuid, pos)
    local uuid2d, pos2d = CACHE.uuid2d, CACHE.pos2d

    local dd = pos2d[pos]
    if not dd or uuid ~= dd.uuid then return false end

    local _, d = assert(remove_obj(self, uuid2d, pos2d, uuid, true))
    return d
end

function _M.remove_notime(self, uuids)
    local uuid2d, pos2d = CACHE.uuid2d, CACHE.pos2d
    local change
    for uuid in pairs(uuids) do
        if remove_obj(self, uuid2d, pos2d, uuid) then change = true end
    end
    if change then sendall(self) end
end

function _M.sort(self, cb)
    local pos2d_old = CACHE.pos2d
    local pos2d = {}
    for _, dd in pairs(pos2d_old) do
        if not checkadd(dd) then table.insert(pos2d, dd) end
    end
    table.sort(pos2d, cb)

    local uuid2d = {}
    for pos, dd in ipairs(pos2d) do
        dd.pos = pos
        local uuid = dd.uuid
        if uuid then uuid2d[uuid] = dd end
    end
    cache.get(self).synctbl = pos2d
    cache.dirty(self)
    CACHE = {uuid2d = uuid2d, pos2d = pos2d}
    sendall(self)
end

function _M.herobest_change(self)
    local uuid2d = CACHE.uuid2d
    for uuid in pairs(uuid2d) do event.occur("EV_HERO_SYNCCHG", self, uuid) end
end

function _M.check(_, uuid)
    return CACHE.uuid2d[uuid] ~= nil
end

function _M.slot_open(self, pos)
    local C = cache.get(self)

    local open = pos - defaultsz(self, C)
    local start = (C.open or 0)
    if start >= open then return false, 1 end

    local cost = uaward()
    for i = start + 1, open do
        local opencfg = HEROSYNC_LATTICE[i]
        if not opencfg then return false, 2 end
        cost.append_one(opencfg.cost)
    end

    local ok, err = award.del(self,
        {flag = "slot_open", arg1 = open, arg2 = start}, cost.result)
    if not ok then return false, err end

    C.open = open
    cache.dirty(self)

    task.trigger(self, "sync", open)
    return true
end

function _M.slot_buy(self, pos)
    local C = cache.get(self)

    local open = pos - defaultsz(self, C)
    if open ~= (C.open or 0) + 1 then return false, 1 end

    if not HEROSYNC_LATTICE[open] then return false, 2 end

    local buy = (C.buy or 0) + 1
    local buycfg = HEROSYNC_BUY[buy]
    if not buycfg then return false, 2 end -- buy max

    local ok, err = award.del(self,
        {flag = "slot_buy", arg1 = open, arg2 = buy}, {buycfg.cost})
    if not ok then return false, err end

    C.open, C.buy = (C.open or 0) + 1, buy
    cache.dirty(self)

    task.trigger(self, "sync", C.open)
    return true
end

function _M.sendall(self)
    sendall(self)
end

require("hero.mod").reg {
    name = "lvlsync",
    load = function(self)
        local C = cache.get(self)
        local pos2d = C.synctbl
        if not pos2d then
            pos2d = {}
            C.synctbl = pos2d
            cache.dirty(self)
        end
        local uuid2d = {}
        for _, info in pairs(pos2d) do
            if info.uuid then uuid2d[info.uuid] = info end
        end
        CACHE = {uuid2d = uuid2d, pos2d = pos2d}
    end,
    enter = function(self)
        sendall(self)
    end
}

return _M
