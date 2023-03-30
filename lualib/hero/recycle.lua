local skynet = require "skynet"
local hinit = require "hero"
local hlock = require "hero.lock"
local cfgproxy = require "cfg.proxy"
local uaward = require "util.award"
local awardtype = require "role.award.type"
local utable = require "util.table"
local award = require "role.award"
local hattrs = require "hero.attrs"
local _H = require "handler.client"
local heqbag = require "hero.eqbag"
local chipbag = require "hero.chipbag"
local event = require "role.event"
local fnopen = require "role.fnopen"
local condition = require "role.condition"
local ctype = require "role.condition.type"
local task = require "task"

require "hero.level"

local insert = table.insert
local query = hinit.query
local query_cfg = hinit.query_cfg
local query_cfg_byid = hinit.query_cfg_byid
local mixture = utable.mixture

local CFG_LV, BASIC

skynet.init(function()
    CFG_LV, BASIC = cfgproxy("hero_level", "basic")
end)

local function check_full(self, uuids, mark)
    local C = hinit.query_all(self)
    local return_items, takeoff_equip = uaward(), {}
    local eqcnt, chipcnt = 0, 0
    local tp_equip, tp_chip = awardtype.equip, awardtype.chip

    for _, uuid in ipairs(uuids) do
        local hero = assert(C[uuid])
        local cfg = query_cfg_byid(self, hero.id)
        return_items.append(CFG_LV[hero.lvreal].return_con, cfg[mark])

        for _, eqdata in pairs(hero.equips or {}) do
            eqcnt = eqcnt + 1
            insert(takeoff_equip, eqdata.uuid)
        end
        for _ in pairs(hero.chips or {}) do chipcnt = chipcnt + 1 end
    end
    eqcnt = eqcnt + return_items.getcnt(tp_equip)
    if heqbag.isfull(self, eqcnt) then return false, award.full_e(tp_equip) end

    chipcnt = chipcnt + return_items.getcnt(tp_chip)
    if chipbag.isfull(self, chipcnt) then return false, award.full_e(tp_chip) end

    local ok, err = award.checkadd(self, return_items.result)
    if not ok then return false, err end

    return return_items.result, takeoff_equip
end

local COST_FUNC = {}
COST_FUNC[1] = function(self, cost, cfg_cost, tbl, u_tbl)
    assert(cost, "cost of stageup wrong")
    local uuids = cost.uuids
    local cfg_id, cfg_cnt = cfg_cost[1], cfg_cost[2]
    local cnt = 0
    for _, uuid in ipairs(uuids) do
        if u_tbl[uuid] then return false, 3 end

        local hero = query(self, uuid)
        if hero.id ~= cfg_id then return false, 5 end

        if hlock.check(self, uuid) then return false, 8 end

        cnt = cnt + 1
        insert(tbl, uuid)
        u_tbl[uuid] = true
    end
    if cfg_cnt ~= cnt then return false, 4 end
    return true
end

COST_FUNC[2] = function(self, cost, cfg_cost, tbl, u_tbl)
    assert(cost, "cost of stageup wrong")
    local uuids = cost.uuids
    local feature, stage, cfgcnt = cfg_cost[1], cfg_cost[2], cfg_cost[3]
    local cnt = 0
    for _, uuid in ipairs(uuids) do
        if u_tbl[uuid] then return false, 3 end

        local obj = query_cfg(self, uuid)
        if obj.stage ~= stage or obj.feature ~= feature then
            return false, 6
        end

        if hlock.check(self, uuid) then return false, 8 end

        cnt = cnt + 1
        insert(tbl, uuid)
        u_tbl[uuid] = true
    end
    if cfgcnt ~= cnt then return false, 4 end
    return true
end

COST_FUNC[3] = function(self, _, cfg_cost)
    return award.checkdel(self, {cfg_cost})
end

local function check_cost(self, costs, cfg, u_tbl)
    local tbl = {}
    for idx, func in pairs(COST_FUNC) do
        local flag = "cost" .. idx
        local cfg_cost = cfg[flag]
        if cfg_cost then
            local ok, e = func(self, costs[flag], cfg_cost, tbl, u_tbl)
            if not ok then return false, e end
        end
    end
    return tbl
end

function _H.hero_stageup(self, msg)
    local uuid = msg.uuid
    local hero = query(self, uuid)

    local id = hero.id
    local cfg = query_cfg_byid(self, id)
    local tar_id = cfg.advanced
    if not tar_id then return {e = 2} end

    local costs = msg.costs
    local uuids, err = check_cost(self, costs, cfg, {[uuid] = true})
    if not uuids then return {e = err} end

    local return_items, takeoff_equip = check_full(self, uuids, "return_res")
    if not return_items then return {e = takeoff_equip} end

    local old = hattrs.pack(self, hero)
    local option = {flag = "hero_stageup", arg1 = uuid, arg2 = tar_id}
    local cost_3 = cfg.cost3

    hinit.dels(self, uuids, option)
    if cost_3 then assert(award.del(self, option, {cost_3})) end

    local new = hinit.inherit(self, uuid, tar_id, option)

    assert(award.add(self, option, return_items))
    event.occur("EV_HERO_STAGEUP", self, {[uuid] = tar_id})
    local cfg_tar = query_cfg_byid(self, tar_id)
    local tar_stage, tar_feature = cfg_tar.stage, cfg_tar.feature

    task.trigger(self, "hero_stageup")

    task.trigger(self, {
        maintype = string.format("hero_stageup_%d_at", tar_feature),
        arg = tar_stage
    }, uuid)

    task.trigger(self, {maintype = "hero_get_at", arg = tar_stage}, uuid)

    task.trigger(self, {
        maintype = string.format("hero_get_%d_at", tar_feature),
        arg = tar_stage
    }, cfg_tar.tab)

    return {
        e = 0,
        new = new,
        old = old,
        return_items = uaward.pack(return_items),
        takeoff_equip = takeoff_equip
    }
end

local function onekey_check(self, list)
    local tar_ids, del_uuids, u_tbl, del_items = {}, {}, {}, uaward()
    for _, v in ipairs(list) do
        local uuid, costs = v.uuid, v.costs
        if u_tbl[uuid] then return false, 3 end
        u_tbl[uuid] = true

        local obj = query(self, uuid)
        local cfg = query_cfg_byid(self, obj.id)
        local tar_id = cfg.advanced
        if not tar_id then return false, 2 end
        local uuids, err = check_cost(self, costs, cfg, u_tbl)
        if not uuids then return false, err end

        mixture(del_uuids, uuids)
        local cost_3 = cfg["cost3"]
        if cost_3 then del_items.append_one(cost_3) end
        tar_ids[uuid] = tar_id
    end
    local ok, err = award.checkdel(self, del_items.result)
    if not ok then return false, err end

    local return_items, takeoff_equip =
        check_full(self, del_uuids, "return_res")
    if not return_items then return false, takeoff_equip end

    return tar_ids, del_uuids, del_items.result, return_items, takeoff_equip
end

local function onekey_execute(self, tar_ids, del_uuids, del_items, return_items,
    takeoff_equip)
    if not tar_ids then return false, del_uuids end

    local logs = {flag = "hero_stage_onekey"}
    hinit.dels(self, del_uuids, logs)
    assert(award.deladd(self, logs, del_items, return_items))
    local heroes, _tar_ids, cfgs = hinit.inherit_onekey(self, tar_ids, logs)
    return heroes, _tar_ids, cfgs, return_items, takeoff_equip
end

function _H.hero_stageup_onekey(self, msg)
    local heroes, tar_ids, cfgs, return_items, takeoff_equip =
        onekey_execute(self, onekey_check(self, msg.list))
    if not heroes then return {e = tar_ids} end
    event.occur("EV_HERO_STAGEUP", self, tar_ids)

    for uuid, cfg in pairs(cfgs) do
        local cfg_stage = cfg.stage
        local feature = cfg.feature
        task.trigger(self, "hero_stageup")
        task.trigger(self, {
            maintype = string.format("hero_stageup_%d_at", feature),
            arg = cfg.stage
        }, uuid)

        task.trigger(self, {maintype = "hero_get_at", arg = cfg_stage}, uuid)

        task.trigger(self, {
            maintype = string.format("hero_get_%d_at", feature),
            arg = cfg_stage
        }, cfg.tab)
    end
    return {
        e = 0,
        heroes = heroes,
        return_items = uaward.pack(return_items),
        takeoff_equip = takeoff_equip
    }
end

local function check_resolve(self, uuids)
    for _, uuid in ipairs(uuids) do
        local obj = query(self, uuid)
        if not obj then return false, 11 end

        if hlock.check(self, uuid) then return false, 8 end
        if not query_cfg_byid(self, obj.id).return_res then
            return false, 10
        end
    end
    return true
end

local nm2 = "recycle"
function _H.hero_resolve(self, msg)
    if not fnopen.check_open(self, nm2) then return {e = 1} end
    local uuids = msg.uuids
    local cnt = #uuids
    if cnt == 0 then return {e = 2} end
    local ok, err = check_resolve(self, uuids)
    if not ok then return {e = err} end
    local return_items, takeoff_equip = check_full(self, uuids, "return_res")
    if not return_items then return {e = takeoff_equip} end

    local option = {flag = "hero_resolve"}
    hinit.dels(self, uuids, option)
    assert(award.add(self, option, return_items))
    task.trigger(self, "hero_resolve", cnt)
    return {
        e = 0,
        uuids = uuids,
        return_items = uaward.pack(return_items),
        takeoff_equip = takeoff_equip
    }
end

function _H.hero_reset(self, msg)
    if not fnopen.check_open(self, nm2) then return {e = 1} end

    local cfg_cost = {BASIC.hero_reset_cost}
    local uuid = msg.uuid
    local obj = query(self, uuid)
    if hlock.check(self, uuid) then return {e = 2} end

    local lvreal = obj.lvreal
    if lvreal == 1 then return {e = 3} end

    local ok, err = award.checkdel(self, cfg_cost)
    if not ok then return {e = err} end

    local return_items, takeoff_equip = check_full(self, {uuid})
    if not return_items then return {e = takeoff_equip} end

    local option = {flag = "hero_reset", arg1 = uuid}
    local new, old = hinit.reset(self, uuid, option)
    assert(award.deladd(self, option, cfg_cost, return_items))
    task.trigger(self, "hero_reset")
    return {
        e = 0,
        old = old,
        new = new,
        return_items = uaward.pack(return_items),
        takeoff_equip = takeoff_equip
    }
end

local function back_check(self, cfg_tab, cfg_stage, condi_cnt)
    local cnt, max_stage = 0, 0
    local tab_list = hinit.query_tab(self, cfg_tab)
    for stage, list in pairs(tab_list) do
        cnt = cnt + #list
        if #list > 0 and stage > max_stage then max_stage = stage end
    end
    if cnt < condi_cnt then return false, 7 end
    if cfg_stage == max_stage then
        if #tab_list[max_stage] <= 1 then return false, 8 end
    end
    return true
end

function _H.hero_back(self, msg)
    if not fnopen.check_open(self, nm2) then return {e = 1} end
    if not fnopen.check_open(self, "hero_back") then return {e = 2} end

    local cost, condi = {BASIC.hero_back_cost}, BASIC.hero_back_condition
    local uuid = msg.uuid
    if hlock.check(self, uuid) then return {e = 3} end

    local ok, err = award.checkdel(self, cost)
    if not ok then return {e = err} end

    local cfg = query_cfg(self, uuid)
    local cfg_stage, cfg_tab = cfg.stage, cfg.tab
    if cfg_stage < condi[1] then return {e = 4} end

    ok, err = back_check(self, cfg_tab, cfg_stage, condi[2])
    if not ok then return {e = err} end

    local return_items, takeoff_equip = check_full(self, {uuid}, "back_res")
    if not return_items then return {e = takeoff_equip} end

    local option = {flag = "hero_back", arg1 = uuid}
    assert(award.deladd(self, option, cost, return_items))
    hinit.dels(self, {uuid}, option)
    return {
        e = 0,
        return_items = uaward.pack(return_items),
        takeoff_equip = takeoff_equip
    }
end

condition.reg(ctype.hero_stage_cnt, function(self, cfg_stage, cfg_cnt)
    return hinit.check_tabcnt(self, cfg_stage, cfg_cnt or 1)
end)
