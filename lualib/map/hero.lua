local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local objmgr = require "map.objmgr"
local map_attrs = require "map.attrs"
local iface = require "battleiface"
local cache = require("map.cache")("temporary_heroes")
local schema = require "mongo.schema"
local env = require "map.env"
local lock = require("skynet.queue")()
local _LUA = require "handler.lua"
local uattrs = require "util.attrs"
local uniq = require "uniq.c"
local source = require "map.source"

local HERO_TOWER, HTOWER_LEVEL, HERO_SECRETACT, CFG_HERO, BASIC
skynet.init(function()
    HERO_TOWER, HTOWER_LEVEL, HERO_SECRETACT, CFG_HERO, BASIC =
        cfgproxy("herotower", "herotower_level", "secretact_hero", "hero",
            "basic")
end)

cache.schema(schema.MAPF("uuid"))

local _M = {}

-- 0 默认(背包英雄+地图获得英雄)
-- 1 只能用herotower里面获得的英雄
-- 2 只能用配置提供的英雄，来了就有

require "util"

local function get_obj(o, lv_average)
    local id = o.id
    local _source = assert(o.source)
    local cfg, level, passive_list

    if _source == source.herotower then
        level = assert(lv_average)
        cfg = HTOWER_LEVEL[level]
        passive_list = HERO_TOWER[o.group][id].effect
    elseif _source == source.secretact_new then
        level = assert(o.level)
        cfg = HERO_SECRETACT[o.group][id]
        passive_list = cfg.effect
    end
    return {
        uuid = o.uuid,
        id = id,
        level = level,
        attrs = iface.temphero_attrs(id, level, cfg.attrs, cfg.attrs_extra),
        passive_list = passive_list
    }
end

local function force_fight_with_local()
    local lineup, lv_average = objmgr.agent_call("explore_query_lineup_only",
        env.mod_nm)
    local heroes, TAB, POS = {}, {}, {}
    local map_heroes = cache.get()
    local dead_heroes = map_attrs.get_dead()

    local pick = {}
    for _, v in ipairs(lineup) do
        local uuid = v.uuid
        local o = map_heroes[uuid]
        if o and not dead_heroes[uuid] then
            local id = o.id
            local obj = get_obj(o, lv_average)
            table.insert(heroes,
                iface.hero(obj, obj.attrs, v.pos, obj.passive_list))

            pick[uuid] = true
            TAB[CFG_HERO[id].tab] = true
            POS[v.pos] = true
        end
    end
    if #heroes >= BASIC.battlemax then return heroes end

    local pool = {}
    for uuid, o in pairs(map_heroes) do
        if not pick[uuid] and not dead_heroes[uuid] then
            local id = o.id
            local tab = CFG_HERO[id].tab
            if not TAB[tab] then
                local obj = get_obj(o, lv_average)
                obj.tab = tab
                obj.zdl = uattrs.zdl(obj.attrs)
                table.insert(pool, obj)
            end
        end
    end

    table.sort(pool, function(a, b)
        return a.zdl > b.zdl
    end)
    local i = 1
    for _, v in ipairs(BASIC.explore_force_format) do
        if not POS[v] then
            while pool[i] do
                local o = pool[i]
                i = i + 1
                local tab = o.tab
                if not TAB[tab] then
                    TAB[tab] = true
                    POS[v] = true
                    table.insert(heroes, iface.hero(o, o.attrs, v, o.effect))
                    break
                end
            end
            if #heroes >= BASIC.battlemax then return heroes end
        end
    end
    return heroes
end

local FORCE_FIGHT = {
    [0] = function()
        -- 单独call一次询问等级，就能在本模块内算出obj的attrs，为了解耦
        local lv_average = objmgr.agent_call("explore_query_lineup")
        local map_heroes = {}
        for _, o in pairs(cache.get()) do
            map_heroes[o.uuid] = get_obj(o, lv_average)
        end
        return objmgr.agent_call("explore_query_lineup", env.mod_nm, map_heroes,
            map_attrs.get_dead())
    end,
    [1] = force_fight_with_local,
    [2] = force_fight_with_local
}

local function force_fight_lineup_generate(type)
    local func = FORCE_FIGHT[type or 0]
    return function()
        return lock(func)
    end
end

local function check_create_generate(forbid_real)
    return function(list)
        local C = cache.get()
        local heroes, simple = {}, {}
        local check = {}
        local cfg
        for _, v in ipairs(list) do
            local uuid, tab, obj = v.uuid, v.tab, v.obj
            local hero, id
            if tab then
                if forbid_real then return false, 111 end
                if check[tab] then return false, 104 end
                check[tab] = true
                id = obj.id
                hero = iface.hero(obj, v.attrs, v.pos, v.passive_list)

                local lasthp, lasttpv = map_attrs.query_left(uuid,
                    hero.baseattrs)
                if lasthp == 0 then return false, 105 end
                hero.lasthp = lasthp
                hero.lasttpv = lasttpv
                cfg = CFG_HERO[id]
            else
                local o = C[uuid]
                if not o then return false, 103 end

                id = o.id
                cfg = CFG_HERO[id]
                tab = cfg.tab
                if check[tab] then return false, 104 end

                check[tab] = true
                obj = get_obj(o, obj.level) -- 用传过来的obj的等级重新生存一次obj
                hero = iface.hero(obj, obj.attrs, v.pos, obj.passive_list)

                local lasthp, lasttpv = map_attrs.query_left(uuid,
                    hero.baseattrs)
                if lasthp == 0 then return false, 105 end
                hero.lasthp = lasthp
                hero.lasttpv = lasttpv
            end
            table.insert(heroes, hero)
            table.insert(simple, {id = id, feature = cfg.feature, tab = tab})
        end
        return heroes, simple
    end
end

local function get_real_heroes(feature)
    return objmgr.agent_call("explore_query_heroes", feature)
end

local function get_map_heroes(feature, real_heroes)
    for uuid, o in pairs(cache.get()) do
        if feature == 0 or CFG_HERO[o.id].feature == feature then
            real_heroes[uuid] = o.id
        end
    end
    return real_heroes
end

local function get_all_generate(type)
    return function(feature)
        local real_heroes = type and {} or lock(get_real_heroes, feature)
        return get_map_heroes(feature, real_heroes)
    end
end

require("map.mods") {
    name = "hero",
    init = function(ctx)
        local type = ctx.hero_mode
        _M.force_fight_lineup = force_fight_lineup_generate(type)
        _M.check_create = check_create_generate(type)
        _M.get_all = get_all_generate(type) -- "全部英雄"的含义取决于类型type
    end,
    new = function(ctx)
        local type = ctx.hero_mode
        local para = ctx.para
        if type == 2 then
            local group = assert(para[1])
            local cfgs = HERO_SECRETACT[group]
            for id, cfg in pairs(cfgs) do
                _M.add({id = id, group = group, level = cfg.level},
                    source.secretact_new)
            end
        end
    end,
    enter = function()
        objmgr.clientpush("map_temporary_heroes", {heroes = cache.get()})
    end
}

-- 英雄塔里面获得的英雄有group没有level
-- secretact 中获得的英雄有level 没有group
function _M.add(o, _source)
    assert(o.id and not o.uuid)
    o.uuid = uniq.uuid()
    o.source = assert(_source)

    local C = cache.get()
    C[o.uuid] = o
    cache.dirty()

    objmgr.clientpush("map_hero_add", {hero = o})
end

function _LUA.map_hero_dels(uuids)
    for _, uuid in ipairs(uuids) do map_attrs.del(uuid) end
end

return _M
