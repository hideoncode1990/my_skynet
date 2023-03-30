local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local mode = require "map.fight_mode"
local cache = require("map.cache")("fightattrs")
local umath = require "util.math"
local supply = require "map.supply"
local map_buff = require "map.buff"
local schema = require "mongo.schema"
local objmgr = require "map.objmgr"

local floor = math.floor

local HERO_CFG, BASIC, DEAD
skynet.init(function()
    HERO_CFG, BASIC = cfgproxy("hero", "basic")
end)

cache.schema(schema.OBJ {
    left = schema.MAPF("uuid"),
    right = schema.SAR(schema.MAPF("pos"))
})

local FULL<const> = 10000

local _M = {}

local function per2val(a, b)
    return floor(a * b / FULL)
end

local function val2per(a, b)
    local per = math.min(floor(a / b * FULL), FULL)
    if per == 0 and a > 0 then per = 1 end
    return per
end

_M.per2val = per2val

function _M.query_left(uuid, attrs)
    local lattrs = cache.getsub("left")[uuid]
    if lattrs then
        return per2val(attrs.hpmax, lattrs.hp_percent),
            per2val(attrs.tpvmax, lattrs.tpv_percent)
    end
end

function _M.query_right(uuid)
    return cache.getsub("right")[uuid]
end

local function deal_ret_normal(ret, heroes, monsters, muuid)
    local hp_left, hp_right = {}, nil
    local push_left, push_right = {}, nil
    local win = ret.win
    local left, right = ret.left, ret.right
    local battle_end_recover = map_buff.passive_table("battle_end_recover")
    for _, v in pairs(heroes) do
        local uuid = v.id
        local info = assert(left[uuid])
        local hp_percent = 0
        if win == 1 then
            local rest_per = val2per(info.hp, v.baseattrs.hpmax)
            if rest_per > 0 then
                local lost_per = FULL - rest_per
                local add_per = floor(lost_per * battle_end_recover)
                hp_percent = rest_per + add_per
            end
        end
        local d = {
            hp_percent = hp_percent,
            tpv_percent = val2per(info.tpv, v.baseattrs.tpvmax),
            uuid = uuid,
            id = v.cfgid
        }
        hp_left[uuid] = d
        push_left[uuid] = d
    end
    local the_left = cache.getsub("left")
    for uuid, info in pairs(hp_left) do the_left[uuid] = info end

    if muuid then
        hp_right, push_right = {}, {muuid = muuid, postbl = {}}
        for _, v in pairs(monsters) do
            local uuid, pos = v.id, v.pos
            local info = assert(right[uuid])
            local hp_percent = val2per(info.hp, v.baseattrs.hpmax)
            local tpv_percent = val2per(info.tpv, v.baseattrs.tpvmax)
            hp_right[pos] = {
                hp_percent = hp_percent,
                tpv_percent = tpv_percent,
                pos = pos
            }
            table.insert(push_right.postbl, {
                hp_percent = hp_percent,
                tpv_percent = tpv_percent,
                pos = pos
            })
        end
        local the_right = cache.getsub("right", muuid)
        for pos, info in pairs(hp_right) do the_right[pos] = info end
    end

    cache.dirty()

    ret.left = hp_left
    ret.right = hp_right

    objmgr.clientpush("map_last_attrs_new",
        {heroes = push_left, monster = push_right})
    return ret
end

local function deal_ret_for_supply(ret, heroes)
    local hp_total, hpmax_total = 0, 0
    for _, v in pairs(heroes) do
        local uuid = v.id
        local info = assert(ret.left[uuid])
        hp_total = hp_total + (info.hp or 0)
        hpmax_total = hpmax_total + v.baseattrs.hpmax
    end
    local supply_del = math.min((hpmax_total - hp_total) / hpmax_total *
                                    BASIC.crack_limit_percent, 0.1)
    supply_del = umath.round(supply_del * BASIC.crack_limit_supply)
    if supply_del > 0 then supply.del(supply_del) end
    return ret
end

function _M.set_last_attrs(heroes, monsters, muuid)
    local the_left = cache.getsub("left")
    for uuid, info in pairs(heroes) do the_left[uuid] = info end
    if muuid then
        local the_right = cache.getsub("right", muuid)
        for pos, info in pairs(monsters) do the_right[pos] = info end
    end
    cache.dirty()
end

-- 能被加血的英雄一定是残血，残血一定被存在the_left中
-- 所以直接对the_left所存的uuid 进行加血
function _M.trap_hp_add(val, feature)
    local the_left = cache.getsub("left")

    for _, o in pairs(the_left) do
        if o.hp_percent > 0 and
            (feature == 0 or feature == HERO_CFG[o.id].feature) then
            o.hp_percent = math.min(o.hp_percent + val, FULL)
        end
    end
    cache.dirty()
    objmgr.clientpush("map_last_attrs_new", {heroes = the_left})
end

function _M.trap_hp_del(val, feature, list)
    local the_left = cache.getsub("left")
    for uuid, id in pairs(list) do
        if feature == 0 or feature == HERO_CFG[id].feature then
            local o = the_left[uuid]
            if not o then
                o = {hp_percent = FULL, id = id, tpv_percent = 0, uuid = uuid}
                the_left[uuid] = o
            end
            o.hp_percent = math.max(o.hp_percent - val, 0)
            if o.hp_percent == 0 and DEAD then DEAD[uuid] = true end
        end
    end
    objmgr.clientpush("map_last_attrs_new", {heroes = the_left})
end

local function get_dead()
    if not DEAD then
        local c = {}
        for uuid, info in pairs(cache.getsub("left")) do
            if info.hp_percent == 0 then c[uuid] = true end
        end
        DEAD = c
    end
    return DEAD
end

_M.get_dead = get_dead

function _M.heal_revival_random(cnt)
    assert(cnt >= 0) -- 参数cnt=0 是策划约定表示复活所有
    local the_left = cache.getsub("left")
    local dead = get_dead()

    local list = {}
    for uuid in pairs(dead) do table.insert(list, uuid) end
    local num = #list

    local some = false
    if #list == 0 then
        return
    elseif cnt == 0 or num <= cnt then
        for _, uuid in ipairs(list) do
            local info = the_left[uuid]
            assert(info.hp_percent == 0)
            info.hp_percent = FULL
        end
    else
        some = {}
        for _ = 1, cnt do
            local pos = math.random(1, #list)
            local uuid = list[pos]
            table.remove(list, pos)
            local info = the_left[uuid]
            assert(info.hp_percent == 0)
            info.hp_percent = FULL
            some[uuid] = info
            if DEAD then DEAD[uuid] = nil end
        end
        num = cnt
    end
    objmgr.clientpush("map_last_attrs_new",
        {heroes = some and some or the_left, heal_1 = num})
end

function _M.heal_cure_live_only(per)
    local some = {}
    local the_left = cache.getsub("left")
    local spring_extra_recover = map_buff.passive_table("spring_extra_recover")
    for uuid, info in pairs(the_left) do
        if info.hp_percent ~= 0 then
            info.hp_percent = math.min(info.hp_percent +
                                           floor(
                    per * 100 * (1 + spring_extra_recover)), FULL)
            some[uuid] = info
        end
    end
    if next(some) then
        cache.dirty()
        objmgr.clientpush("map_last_attrs_new", {heroes = some})
    end
end

function _M.heal_all_full(all_heroes) -- 血和怒气全满
    local the_left = cache.getsub("left")
    for uuid, id in pairs(all_heroes) do
        local info = the_left[uuid]
        if info then
            local old = info.hp_percent
            info.hp_percent = FULL
            info.tpv_percent = FULL
            if old == 0 and DEAD then old[uuid] = nil end
        else
            the_left[uuid] = {
                uuid = uuid,
                id = id,
                hp_percent = FULL,
                tpv_percent = FULL
            }
        end
    end
    cache.dirty()
    -- heal_3 的值没有意义，仅用于辨识类型
    objmgr.clientpush("map_last_attrs_new", {heroes = the_left, heal_3 = -1})
end

function _M.del(uuid)
    local the_left = cache.getsub("left")
    if the_left[uuid] then
        the_left[uuid] = nil

        cache.dirty()
    end
end

require("map.mods") {
    name = "attrs",
    init = function(ctx)
        local fight_mode = ctx.fight_mode
        if not fight_mode then
            _M.deal_ret = deal_ret_normal
        elseif fight_mode == mode.supply then
            _M.deal_ret = deal_ret_for_supply
        end
    end,
    enter = function()
        local heroes = cache.getsub("left")
        local d_right = cache.getsub("right")
        local right = {}
        for muuid, v in pairs(d_right or {}) do
            local postbl = {}
            local t = {muuid = muuid, postbl = postbl}
            for pos, info in pairs(v) do
                table.insert(postbl, {
                    hp_percent = info.hp_percent,
                    tpv_percent = info.tpv_percent,
                    pos = pos
                })
            end
            table.insert(right, t)
        end
        objmgr.clientpush("map_last_attrs", {heroes = heroes, monsters = right})
    end
}

return _M
