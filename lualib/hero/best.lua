local skynet = require "skynet"
local client = require "client.mods"
local event = require "role.event"
local herosync = require "hero.sync"
local timer = require "timer"
local cfgproxy = require "cfg.proxy"
local umath = require "util.math"
local hero = require "hero"
local flowlog = require "flowlog"
local query_cfg_byid = hero.query_cfg_byid

local BASIC
skynet.init(function()
    BASIC = cfgproxy("basic")
end)

local CACHE = {dict = {}, array = {}}
local LEVEL

local NM<const> = "herobest"

local _M = {}

local function update_inner(self, opt)
    table.sort(CACHE.array, function(l, r)
        local lvreal_l, lvreal_r = l.lvreal, r.lvreal
        if lvreal_l == lvreal_r then
            return query_cfg_byid(self, l.id).stage >
                       query_cfg_byid(self, r.id).stage
        else
            return lvreal_l > lvreal_r
        end
    end)
    local listchg = false
    local dict_old, array = CACHE.dict, CACHE.array
    local dict = {}
    CACHE.dict = dict

    for i = 1, BASIC.herobest_count do
        local obj = array[i]
        if not obj then break end

        local uuid = obj.uuid
        dict[uuid] = true
        if not dict_old[uuid] then
            listchg = true
        else
            dict_old[uuid] = nil
        end
    end
    if listchg == false and next(dict_old) then listchg = true end

    local lv_obj = CACHE.array[BASIC.herobest_count]
    local level = 1
    if lv_obj then level = lv_obj.lvreal end

    if listchg then herosync.remove_notime(self, dict) end

    local before = LEVEL
    local lvchg = LEVEL ~= level
    if lvchg then
        LEVEL = level
        herosync.herobest_change(self)
        flowlog.role(self, "herosync",
            {flag = NM, before = before, now = level, opt = opt})
    end

    return listchg, lvchg
end

function _M.init(self, list)
    if herosync.build(self) then return end
    for uuid, obj in pairs(list) do
        assert(not CACHE.dict[uuid])
        table.insert(CACHE.array, obj)
    end
    update_inner(self)
end

function _M.add(self, obj)
    if herosync.build(self) then return end
    assert(not CACHE.dict[obj.uuid])
    table.insert(CACHE.array, obj)
    _M.update(self, "add")
end

function _M.remove(self, uuid)
    if herosync.build(self) then return end
    for idx, obj in ipairs(CACHE.array) do
        if uuid == obj.uuid then
            table.remove(CACHE.array, idx)
            _M.update(self, "remove")
            break
        end
    end
end

function _M.enter(self)
    local list = {}
    if not herosync.build(self) then
        for i = 1, BASIC.herobest_count do
            local obj = CACHE.array[i]
            if not obj then break end
            table.insert(list, obj.uuid)
        end
    end
    client.enter(self, NM, "herobest_list", {list = list})
end

function _M.try_build(self)
    if herosync.build(self) then return end
    if LEVEL < BASIC.herobest_build_level then return end

    herosync.build_change(self, LEVEL)
    local option = {flag = "herobest"}
    for uuid in pairs(CACHE.dict) do
        hero.reset(self, uuid, option)
        herosync.add_anyway(self, uuid)
    end
    herosync.sendall(self)
    CACHE = nil
    return true
end

function _M.update(self, opt)
    if herosync.build(self) then return end
    local listchg, lvchg = update_inner(self, opt)

    if lvchg then
        if LEVEL >= BASIC.herobest_build_level then
            assert(_M.try_build(self))
            listchg = true
        end
    end
    if listchg then _M.enter(self) end
end

function _M.check(self, uuid)
    if herosync.build(self) then return false end
    return CACHE.dict[uuid] ~= nil
end

function _M.level(self)
    return herosync.build(self) or LEVEL
end

local function level_top5_average()
    local array = CACHE.array
    local average, sum = 0, 0

    for i, info in ipairs(array) do
        if i > BASIC.herobest_count then
            return average
        else
            sum = sum + info.lvreal
            average = umath.round(sum / i)
        end
    end
    return average
end

function _M.level_top5_average(self) -- 等级前五的平均等级
    return herosync.build(self) or level_top5_average()
end

local top5_cache, top5_dirty = {}, true
local function get_top5_cache(self)
    if top5_dirty then
        top5_cache, top5_dirty = {}, nil
        local list = hero.query_all(self)
        for _, obj in pairs(list) do table.insert(top5_cache, obj) end
        table.sort(top5_cache, function(a, b)
            if a.level == b.level then
                local a_stage = query_cfg_byid(self, a.id).stage
                local b_stage = query_cfg_byid(self, b.id).stage
                return a_stage > b_stage
            else
                return a.level > b.level
            end
        end)
    end
    return top5_cache
end
event.reg("EV_HERO_LVUP", NM, function(self)
    top5_dirty = true
end)
event.reg("EV_HERO_DELS", NM, function(self)
    top5_dirty = true
end)
event.reg("EV_HERO_STAGEUP", NM, function(self)
    top5_dirty = true
end)

function _M.get_top5_heroes(self)
    local array
    if herosync.build(self) then
        array = get_top5_cache(self)
    else
        array = CACHE.array
    end
    local r = {}
    for i, info in ipairs(array) do
        if i > BASIC.herobest_count then break end
        table.insert(r, info.id)
    end
    return r
end

local in_update
event.reg("EV_HERO_LVREAL_UP", "hero_syncbest", function(self)
    if herosync.build(self) then return end
    if not in_update then
        in_update = true
        timer.add(10, function()
            in_update = nil
            _M.update(self)
        end)
    end
end)

event.reg("EV_HERO_STAGEUP", "hero_syncbest", function(self)
    if not in_update then
        in_update = true
        timer.add(10, function()
            in_update = nil
            _M.update(self)
        end)
    end
end)

return _M
