local skynet = require "skynet"
local queue = require "skynet.queue"
local uattrs = require "util.attrs"
local timer = require "timer"
local client = require "client.mods"
local event = require "role.event"
local zset = require "zset"
local task = require "task"
local roleinfo = require "roleinfo.change"
local cfgproxy = require "cfg.proxy"
local zsettype = require "zset.type"
local utable = require "util.table"
local platlog = require "platlog"

local LOCK = queue()

local BASIC
skynet.init(function()
    BASIC = cfgproxy("basic")
end)

local _M = {}
local MODS, MODS_AFTER = {}, {}

local HERO_CACHE, MOD_CACHE, ZDL_CACHE, ZDL_ARR = {}, {}, {}, {}
local HERO_DIRTY = {}
local indirty = {}

function _M.reg(nm, cb)
    MODS[nm] = cb
end

function _M.regafter(nm, cb)
    MODS_AFTER[nm] = cb
end

function _M.mod(self, uuid, name)
    return MOD_CACHE[uuid][name] or MODS[name](self, uuid)
end

local zdl_dirty
local function calc_total_zdl(self)
    if not zdl_dirty then
        zdl_dirty = true
        skynet.fork(function()
            skynet.sleep(10)
            zdl_dirty = nil
            local total = 0
            for _, v in pairs(ZDL_CACHE) do total = total + v.zdl end
            self.zdl = total
            roleinfo.change(self, "zdl", total)
            task.trigger(self, "zdl", total)
            zset.set(zsettype.zdl,
                {id = self.rid, value = total, sid = self.sid})
            client.push(self, "crainfo", "characterinfo_zdl", {zdl = total})
        end)
    end
end

local function calc_attrs(self, uuid)
    local cache = MOD_CACHE[uuid]
    local ret = {}
    for nm, cb in pairs(MODS) do
        local attr = cache[nm]
        if not attr then
            attr = cb(self, uuid)
            cache[nm] = attr
        end
        uattrs.append(ret, attr)
    end
    for _, cb in pairs(MODS_AFTER) do cb(self, uuid, ret) end
    local zdl = uattrs.zdl(ret)
    return ret, zdl
end

local function zdl_arr_sort(self)
    for i = 1, BASIC.herobest_count do
        local m = ZDL_ARR[i]
        if m then
            m.is_topfive = nil
        else
            break
        end
    end

    table.sort(ZDL_ARR, function(a, b)
        return a.zdl > b.zdl
    end)

    local sum = 0
    for i = 1, BASIC.herobest_count do
        local m = ZDL_ARR[i]
        if m then
            sum = sum + m.zdl
            m.is_topfive = i
        else
            break
        end
    end
    skynet.fork(zset.set, zsettype.zdl_topfive,
        {id = self.rid, value = sum, sid = self.sid})
end

local function zdl_topfive(self, zdl, is_topfive)
    local size = BASIC.herobest_count
    local min_zdl = ZDL_ARR[size] and ZDL_ARR[size].zdl or 0
    if not is_topfive and min_zdl >= zdl then return end -- 优化，减少sort

    zdl_arr_sort(self)
end

local function calc_ZDL_CACHE(self, uuid, zdl)
    local tbl = ZDL_CACHE[uuid]
    if tbl then
        tbl.zdl = zdl
    else
        tbl = {uuid = uuid, zdl = zdl}
        ZDL_CACHE[uuid] = tbl
        table.insert(ZDL_ARR, tbl)
    end
    zdl_topfive(self, zdl, tbl.is_topfive)
end

local function hero_attrs(self, uuid)
    local attrs, zdl
    if HERO_DIRTY[uuid] then
        attrs, zdl = calc_attrs(self, uuid)
        HERO_CACHE[uuid] = attrs
        HERO_DIRTY[uuid] = nil
        calc_ZDL_CACHE(self, uuid, zdl)
        calc_total_zdl(self)
    else
        attrs, zdl = HERO_CACHE[uuid], ZDL_CACHE[uuid].zdl
    end
    return attrs, zdl
end

local function calc_dirty(self, uuid, change, pkt)
    local old = HERO_CACHE[uuid] -- 获取缓存的旧值
    HERO_DIRTY[uuid] = true -- 清除缓存
    local new, zdl = hero_attrs(self, uuid) -- 触发重新计算

    local dict = uattrs.compare(new, old)
    change[uuid] = dict
    table.insert(pkt, {uuid = uuid, attrs = uattrs.pack(dict), zdl = zdl})
    return new
end

local function dirty_one(self, uuid)
    HERO_DIRTY[uuid] = true
    local change, list = {}, {}
    local new = calc_dirty(self, uuid, change, list)
    event.occur("EV_HERO_ATTRS_CHANGE", self, change)
    client.push(self, "hero", "hero_attrs_change", {list = list})
    return new
end

local function dirty_some(self)
    local dirtys
    dirtys, indirty = indirty, {}
    local change, list = {}, {}

    for uuid, need in pairs(dirtys) do
        if need and MOD_CACHE[uuid] then
            calc_dirty(self, uuid, change, list)
        end
    end
    if #list > 0 then
        event.occur("EV_HERO_ATTRS_CHANGE", self, change)
        client.push(self, "hero", "hero_attrs_change", {list = list})
    end
end

local function dirty_inner(self, name, uuid)
    if indirty[uuid] then indirty[uuid] = false end
    MOD_CACHE[uuid][name] = nil
    return dirty_one(self, uuid)
end

local function init(self, uuid)
    MOD_CACHE[uuid] = {}
    local attrs, zdl = calc_attrs(self, uuid)
    HERO_CACHE[uuid] = attrs
    calc_ZDL_CACHE(self, uuid, zdl)
end

local function reinit(self, uuid)
    MOD_CACHE[uuid] = {}
    return dirty_one(self, uuid)
end

function _M.zdl_init(self)
    local total = 0
    for _, v in pairs(ZDL_CACHE) do total = total + v.zdl end
    self.zdl = total
end

function _M.init(self, uuid)
    LOCK(init, self, uuid)
end

-- 继承和重置时，对该英雄属性重新初始化
function _M.reinit(self, uuid)
    return LOCK(reinit, self, uuid)
end

function _M.dirty(self, name, ...)
    local n = select("#", ...)
    local is_indirty = next(indirty) ~= nil
    for i = 1, n do
        local uuid = select(i, ...)
        MOD_CACHE[uuid][name] = nil
        indirty[uuid] = true
    end
    if not is_indirty then
        timer.add(10, function()
            LOCK(dirty_some, self)
        end)
    end
end

function _M.dirty_now(self, name, uuid)
    return LOCK(dirty_inner, self, name, uuid)
end

function _M.query(self, uuid)
    return LOCK(hero_attrs, self, uuid)
end

function _M.remove(self, uuid)
    MOD_CACHE[uuid], HERO_CACHE[uuid], ZDL_CACHE[uuid], HERO_DIRTY[uuid] = nil,
        nil, nil, nil
    calc_total_zdl(self)
    for k, v in ipairs(ZDL_ARR) do
        if v.uuid == uuid then
            table.remove(ZDL_ARR, k)
            if v.is_topfive then zdl_arr_sort(self) end
            break
        end
    end
end

-- pack接口会返回hero的拷贝，并将添加筛选后的属性
function _M.pack(self, hero)
    local uuid = hero.uuid
    local attrs, zdl = hero_attrs(self, uuid)
    local _hero = utable.copy(hero)
    _hero.attrs = uattrs.pack(attrs)
    _hero.zdl = zdl
    return _hero
end

return _M
