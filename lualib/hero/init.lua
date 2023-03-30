local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local award = require "role.award"
local awardtype = require "role.award.type"
local client = require "client.mods"
local uniq = require "uniq.c"
local heromod = require "hero.mod"
local flowlog = require "flowlog"
local platlog = require "platlog"
local utable = require "util.table"
local hattrs = require "hero.attrs"
local capacity = require "hero.capacity"
local head = require "role.m_head"
local event = require "role.event"
local utime = require "util.time"
local hero_passive = require "hero.passive"
local task = require "task"
local umath = require "util.math"
local handbook = require "hero.handbook"

local getsub = utable.getsub

local cache = require("mongo.role")("heroes")
local schema = require "mongo.schema"

cache.schema(schema.MAPF("uuid", schema.OBJ {
    uuid = schema.ORI,
    id = schema.ORI,
    lvreal = schema.ORI,
    lvreal_ti = schema.ORI,
    lock = schema.ORI
}))

local insert = table.insert
local remove = table.remove
local sort = table.sort

local NM<const> = "hero"
local CFG, BASIC
local samestage, sametab = {}, {}
local num = 0
local _M = {}

--[[
    [uuid]={
        uuid        唯一id
        id,         英雄id
        lvreal,      --等级
        lock
    }
]]

skynet.init(function()
    CFG, BASIC = cfgproxy("hero", "basic")
end)

local function same_add(stage, tab, uuid)
    local temp = getsub(samestage, stage)
    local list = temp[tab]
    if not list then
        list = {}
        temp[tab] = list
        local temp2 = getsub(sametab, tab)
        temp2[stage] = list
    end
    insert(list, uuid)
end

local function same_del(stage, tab, uuid)
    local tab_tbl = getsub(samestage, stage, tab)
    for k, v in ipairs(tab_tbl) do
        if uuid == v then
            remove(tab_tbl, k)
            if #tab_tbl == 0 then
                samestage[stage][tab] = nil
                sametab[tab][stage] = nil
            end
            return
        end
    end
end

local function hero_flowlog(self, opt, option, hero, cfg, other)
    local info = {
        opt = opt,
        flag = option.flag,
        arg1 = option.arg1,
        arg2 = option.arg2,
        uuid = hero.uuid,
        id = hero.id,
        exclusive = hero.exclusive,
        lvreal = hero.lvreal,
        stage = cfg.stage
    }
    if other then for k, v in pairs(other) do info[k] = v end end
    flowlog.role(self, NM, info)
    if opt == "add" or opt == "del" then
        platlog("item", {
            action = opt == "add" and 1 or -1,
            tp = awardtype.hero,
            id = hero.id,
            flag = option.flag,
            arg1 = option.arg1,
            change = 1,
            last = opt == "add" and 1 or 0
        }, self)
    end
end

local function hero_remove(self, uuid, C, option)
    local hero = assert(C[uuid])
    local cfg = CFG[hero.id]
    same_del(cfg.stage, cfg.tab, uuid)
    heromod.remove(self, uuid, hero, option)
    hattrs.remove(self, uuid)

    C[uuid] = nil
    cache.dirty(self)
    num = num - 1
    hero_flowlog(self, "del", option, hero, cfg)
    return hero
end

require("role.mods") {
    name = "hero_init",
    load = function(self)
        heromod.load(self)
        local C = cache.get(self)
        for uuid, hero in pairs(C) do
            local cfg = CFG[hero.id]
            if cfg then
                heromod.init(self, uuid, hero)
                num = (num or 0) + 1
                same_add(cfg.stage, cfg.tab, uuid)
            else
                C[uuid] = nil
                hero_flowlog(self, "del", {flag = "autodel"}, hero, cfg)
            end
        end
    end,
    loaded = function(self)
        for uuid in pairs(cache.get(self)) do
            hattrs.init(self, uuid)
            hero_passive.init(self, uuid)
        end
        hattrs.zdl_init(self)
        heromod.loaded(self)
    end,
    enter = function(self)
        heromod.enter(self)
        client.enter(self, NM, "hero_list_start", {})
        local list, n = {}, 0
        for _, hero in pairs(cache.get(self)) do
            n = n + 1
            insert(list, hattrs.pack(self, hero))

            if n >= 100 then -- 分包发送，每个包100个英雄信息
                client.push(self, NM, "hero_list", {list = list})
                list = {}
                n = 0
            end
        end
        if next(list) then
            client.push(self, NM, "hero_list", {list = list})
        end
    end
}

local function isfull(self, n)
    return num + (n or 1) > capacity.get(self)
end

local function create(self, C, id, lvreal, option)
    local uuid = uniq.uuid()
    local hero = {
        uuid = uuid,
        id = id,
        lvreal = lvreal or 1,
        lvreal_ti = utime.time()
    }
    C[uuid] = hero
    cache.dirty(self)

    local cfg = CFG[id]
    num = num + 1
    local tab = cfg.tab
    same_add(cfg.stage, tab, uuid)
    heromod.create(self, uuid, hero)
    hattrs.init(self, uuid)
    head.add_by_hero(self, tab)
    handbook.add(self, tab)

    hero_flowlog(self, "add", option, hero, cfg)
    return hero
end

local function reset_same(id_old, new_id, uuid)
    local cfg_o, cfg_n = CFG[id_old], CFG[new_id]
    same_del(cfg_o.stage, cfg_o.tab, uuid)
    same_add(cfg_n.stage, cfg_n.tab, uuid)
end

local function inherit(self, C, uuid, id, option)
    local hero = assert(C[uuid])
    local id_old = hero.id
    hero.id = id
    cache.dirty(self)

    heromod.inherit(self, uuid, hero)
    hattrs.reinit(self, uuid)
    reset_same(id_old, id, uuid)

    hero_flowlog(self, "inherit", option, hero, CFG[id], {id_old = id_old})
    return hero
end

local function hero_create(self, id, C, option)
    local hero = create(self, C, id, 1, option)
    local cfg = CFG[id]
    local cfg_stage = cfg.stage
    task.trigger(self, "hero_get")

    task.trigger(self, {maintype = "hero_get_at", arg = cfg_stage}, hero.uuid)

    task.trigger(self, {
        maintype = string.format("hero_get_%d_at", cfg.feature),
        arg = cfg_stage
    }, cfg.tab)

    return hattrs.pack(self, hero)
end

local function hero_add(self, nms, pkts, option, items)
    local C = cache.get(self)
    local list = pkts.hero_add
    nms.hero_add = NM
    local uuid2id = {}
    for _, cfg in pairs(items) do
        local id, cnt = cfg[2], cfg[3]
        for _ = 1, cnt do
            local pkt = hero_create(self, id, C, option)
            insert(list, pkt)
            uuid2id[pkt.uuid] = pkt.id
        end
    end
    event.occur("EV_HERO_STAGEUP", self, uuid2id)
    return true
end

function _M.dels(self, uuids, option)
    local C = cache.get(self)
    local ret = {}
    for _, uuid in ipairs(uuids) do hero_remove(self, uuid, C, option) end
    event.occur("EV_HERO_DELS", self, uuids)
    client.push(self, NM, "hero_del", {list = uuids})
    return ret
end

function _M.inherit(self, uuid, id, logs)
    local C = cache.get(self)
    local hero = inherit(self, C, uuid, id, logs)

    local hero_copy = hattrs.pack(self, hero)
    client.push(self, NM, "hero_inherit", {list = {hero_copy}})
    return hero_copy
end

function _M.inherit_onekey(self, tar_ids, logs)
    local C = cache.get(self)
    local list, cfgs = {}, {}
    for uuid, tar_id in pairs(tar_ids) do
        logs.arg1 = uuid
        logs.arg2 = tar_id
        local hero = inherit(self, C, uuid, tar_id, logs)
        table.insert(list, hattrs.pack(self, hero))
        cfgs[uuid] = CFG[tar_id]
    end
    client.push(self, NM, "hero_inherit", {list = list})
    return list, tar_ids, cfgs
end

function _M.reset(self, uuid, option)
    local hero = cache.get(self)[uuid]
    local old = hattrs.pack(self, hero)
    hero.lvreal = 1
    hero.lvreal_ti = utime.time()
    cache.dirty(self)

    heromod.reset(self, uuid, hero, option)
    hattrs.reinit(self, uuid)
    client.push(self, NM, "hero_reset", {uuid = uuid})

    hero_flowlog(self, "reset", option, hero, CFG[hero.id],
        {lvreal_old = old.lvreal})
    return hattrs.pack(self, hero), old
end

function _M.levelup(self, uuid, lvreal, option)
    assert(lvreal >= 1)
    local C = cache.get(self)
    local hero = C[uuid]
    local lvreal_old = hero.lvreal
    hero.lvreal = lvreal
    hero.lvreal_ti = utime.time()
    heromod.levelup(self, uuid, hero)
    cache.dirty(self)

    hero_flowlog(self, "levelup", option, hero, CFG[hero.id],
        {lvreal_old = lvreal_old})
end

function _M.update_lock(self, uuid, lock)
    local C = cache.get(self)

    local hero = C[uuid]
    if not hero then return false end

    if lock then
        hero.lock = lock
    else
        hero.lock = nil
    end
    cache.dirty(self)
    return true
end

local function query(self, uuid)
    return cache.get(self)[uuid]
end

function _M.query_all(self)
    return cache.get(self)
end

local function query_cfg(self, uuid)
    local id = cache.get(self)[uuid].id
    return CFG[id]
end

function _M.query_cfg_byid(_, id)
    return CFG[id]
end

function _M.foreach(self, cb)
    for uuid, hero in pairs(cache.get(self)) do cb(hero, uuid) end
end

function _M.explore_query_heroes(self, feature)
    local list = {}
    for uuid, info in pairs(cache.get(self)) do
        local id = info.id
        if feature == 0 or feature == CFG[id].feature then
            list[uuid] = id
        end
    end
    return list
end

-- 大于等于某stage时，是否存在某个tab, 保证至少有cnt个英雄
function _M.check_tabcnt(_, stage, cnt)
    for _, info in pairs(sametab) do
        local total = 0
        for _stage, list in pairs(info) do
            if _stage >= stage then
                total = total + #list
                if total >= cnt then return true end
            end
        end
    end
end

-- 大于等于某个stage时，有多少个tab互不相同的英雄，相同tab算一个
function _M.tabcnt_greater_samestage(_, stage)
    local total, mark = 0, {}
    for k, v in pairs(samestage) do
        if k >= stage then
            for tab in pairs(v) do
                if not mark[tab] then
                    mark[tab] = true
                    total = total + 1
                end
            end
        end
    end
    return total
end

function _M.query_tab(_, tab)
    return sametab[tab]
end

function _M.besthero_in_different_tab(self)
    local arr = {}
    for _, list in pairs(sametab) do
        local zdl_top, uuid_top = -1, nil
        for _, uuids in pairs(list) do
            for _, uuid in ipairs(uuids) do
                local _, zdl = hattrs.query(self, uuid)
                if zdl > zdl_top then
                    zdl_top = zdl
                    uuid_top = uuid
                end
            end
        end
        if uuid_top then insert(arr, {uuid = uuid_top, zdl = zdl_top}) end
    end
    sort(arr, function(a, b)
        return a.zdl > b.zdl
    end)
    return arr
end

function _M.stage_top5_average(_)
    local stages = {}
    for stage in pairs(samestage) do insert(stages, stage) end

    sort(stages, function(a, b)
        return a > b
    end)

    local herobest_count = BASIC.herobest_count
    local average, sum, cnt = 0, 0, 0
    for _, stage in ipairs(stages) do
        local stagesub = samestage[stage]
        for _, list in pairs(stagesub) do
            local listcnt = #list
            if cnt + listcnt >= herobest_count then
                sum = sum + (herobest_count - cnt) * stage
                return umath.round(sum / herobest_count)
            else
                cnt = cnt + listcnt
                sum = sum + listcnt * stage
                if cnt == 0 then
                    average = 0
                else
                    average = umath.round(sum / cnt)
                end
            end
        end
    end
    return average
end

function _M.check_new_tab(self, heroes)
    local ret = {}
    for _, v in ipairs(heroes) do
        if v[1] == awardtype.hero then
            local id = v[2]
            local cfg = CFG[id]
            if not handbook.check(self, cfg.tab) then
                table.insert(ret, id)
            end
        end
    end
    return ret
end

_M.isfull = isfull
_M.query_cfg = query_cfg
_M.query = query

award.reg {
    type = awardtype.hero,
    add = hero_add,
    checkadd = function(self, items)
        local n = 0
        for _, v in ipairs(items) do
            local id, cnt = v[2], v[3]
            local cfg = CFG[id]
            assert(cfg and cfg.ishero and cnt > 0)
            n = n + cnt
        end
        return not isfull(self, n)
    end,
    del = function()
        error("no support")
    end,
    checkdel = function()
        error("no support")
    end
}

return _M
