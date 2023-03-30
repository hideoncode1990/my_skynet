local skynet = require "skynet"
local hattrs = require "hero.attrs"
local heqbag = require "hero.eqbag"
local heqlib = require "hero.eqlib"
local hinit = require "hero"
local cfgproxy = require "cfg.proxy"
local awardtype = require "role.award.type"
local uaward = require "util.award"
local award = require "role.award"
local task = require "task"
local _H = require "handler.client"

local query_eqcfg = heqbag.query_eqcfg
local query_eqbag = heqbag.query_eqbag
local query_eqbody = heqbag.query_eqbody

local NM<const> = "eqbag"

local BAISC, CFG_REFINE, CFG_EXP

skynet.init(function()
    BAISC, CFG_REFINE, CFG_EXP = cfgproxy("basic", "equip_refine", "equip_exp")
end)

heqlib.reg("refine", function(self, equip)
    local id, level = equip.id, equip.level
    local cfg = query_eqcfg(self, id)
    return CFG_REFINE[cfg.mark][level].add
end)

local function calc_coin(use_exp, need_exp, materials, coins)
    local cost = uaward().append_one(materials).multi(use_exp / need_exp)
    coins.append_ctx(cost)
end

local function calc(level, exp, add_exp, refine_cfg, coins, per_exp)
    if not refine_cfg[level + 1] then return false, 1 end

    while true do
        if not refine_cfg[level + 1] then break end
        local cfg_cur = refine_cfg[level]

        local need_exp, materials = cfg_cur.need_exp, cfg_cur.coin
        local overflow = add_exp + exp - need_exp
        if overflow >= 0 then
            calc_coin(need_exp - exp, need_exp, materials, coins)
            level, exp = level + 1, 0
            add_exp = overflow
        else
            exp = exp + add_exp
            calc_coin(add_exp, need_exp, materials, coins)
            add_exp = 0
            break
        end
    end
    if add_exp > 0 then -- 经验溢出处理
        if per_exp and add_exp > per_exp then
            return false, 1
        else
            local cfg_cur = refine_cfg[level]
            local need_exp = cfg_cur.need_exp
            add_exp = math.min(add_exp, need_exp)
            exp = exp + add_exp
        end
    end
    return level, exp
end

local function calccost(self, level, exp, refine_cfg, icost, ecost)
    local costs = uaward()
    local itemtype = awardtype.items
    local basic_refine = BAISC.equip_refine_item
    if icost then
        for _, v in ipairs(icost) do
            local item = v.item
            local id, cnt = item[1], item[2]
            local per_exp = basic_refine[id]
            local add_exp = per_exp * cnt
            level, exp = calc(level, exp, add_exp, refine_cfg, costs, per_exp)
            if not level then return false, exp end
            costs.append_one({itemtype, id, cnt})
        end
    end
    if ecost then
        for _, uuid in ipairs(ecost) do
            local equip = query_eqbag(self, uuid)
            if equip.owner then return false, 3 end

            local cfg = query_eqcfg(self, equip.id)
            local add_exp = CFG_EXP[cfg.mark][equip.level] + cfg.exp
            level, exp = calc(level, exp, add_exp, refine_cfg, costs)
            if not level then return false, exp end
        end
    end
    return costs.result, level, exp
end
function _H.equip_refine(self, msg)
    local uuid, icost, ecost = msg.uuid, msg.item_cost, msg.equip_cost
    assert(next(icost) or next(ecost))

    local equip = query_eqbag(self, uuid)
    if not equip.owner then return {e = 4} end

    local cfg = query_eqcfg(self, equip.id)
    local level, exp = equip.level, equip.exp
    if level >= cfg.level_max then return {e = 1} end

    local refine_cfg = CFG_REFINE[cfg.mark]
    local costs, _level, _exp = calccost(self, level, exp, refine_cfg, icost,
        ecost)
    if not costs then return {e = _level} end

    local ok, e = award.checkdel(self, costs)
    if not ok then return {e = e} end

    local option = {flag = "equip_refine", arg1 = uuid}
    assert(award.del(self, option, costs))
    heqbag.dels(self, ecost, option)
    -- 此处的arg1和arg2记录操作之前的等级和经验，装备日志中，统一记录了操作之后的等级和经验
    option.arg1, option.arg2 = level, exp
    assert(heqbag.refine(self, uuid, _level, _exp, option))
    hattrs.dirty(self, NM, equip.owner)
    task.trigger(self, "equip_refine")
    return {e = 0, uuid = uuid, level = _level, exp = _exp}
end

function _H.equip_feature_change(self, msg)
    local uuid = msg.uuid
    local eqdata = query_eqbag(self, uuid)
    local oldfeature = eqdata.feature
    if not oldfeature then return {e = 1} end

    local cost = query_eqcfg(self, eqdata.id).reset
    if not cost then return {e = 2} end

    local option = {flag = "equip_feature_change", arg1 = oldfeature}
    if not award.del(self, option, {cost}) then return {e = 3} end

    local new_feature = heqbag.refeature(self, uuid, option)
    return {e = 0, new_feature = new_feature}
end

function _H.equip_feature_sure(self, msg)
    local uuid, sure = msg.uuid, msg.sure
    local eqdata = query_eqbag(self, uuid)
    if not eqdata.new_feature then return {e = 1} end

    local option = {
        flag = "equip_feature_sure",
        arg1 = sure,
        arg2 = eqdata.feature or 0
    }
    heqbag.feature_sure(self, uuid, sure, option)
    if eqdata.owner then hattrs.dirty(self, NM, eqdata.owner) end
    return {e = 0}
end

local function check_cfg(self, hero_uuid, uuids, hero_job)
    local pos_tbl, temp = {}, {}
    for _, uuid in ipairs(uuids) do
        local eqdata = query_eqbag(self, uuid)
        local id = eqdata.id
        local cfg = query_eqcfg(self, id)
        if hero_job ~= cfg.job then return false, 1 end
        local pos = cfg.pos
        if temp[pos] then return false, 2 end
        local owner = eqdata.owner
        if owner and owner == hero_uuid then return false, 3 end
        temp[pos] = true
        table.insert(pos_tbl, pos)
    end
    return pos_tbl
end

function _H.equip_puton(self, msg)
    local hero_uuid, uuid, pos = msg.hero_uuid, msg.uuid, msg.pos
    local cfg_hero = hinit.query_cfg(self, hero_uuid)
    local eqdata = query_eqbag(self, uuid)
    local cfg_equip = query_eqcfg(self, eqdata.id)

    if cfg_hero.job ~= cfg_equip.job then return {e = 1} end
    if pos ~= cfg_equip.pos then return {e = 2} end
    if eqdata.pos and hero_uuid == eqdata.owner then return {e = 3} end

    local dirty_uuids, samemark = heqbag.puton(self, hero_uuid, {uuid}, {pos}, {
        flag = "equip_puton",
        arg1 = hero_uuid,
        arg2 = uuid
    })
    hattrs.dirty(self, NM, table.unpack(dirty_uuids))

    for _, v in ipairs(samemark) do
        for mark, cnt in pairs(v) do
            task.trigger(self, "eqbody_stage_at" .. mark, cnt)
        end
    end

    return {e = 0}
end

function _H.equip_puton_onekey(self, msg)
    local hero_uuid, uuids = msg.hero_uuid, msg.uuids
    local cfg_hero = hinit.query_cfg(self, hero_uuid)

    local postbl, e = check_cfg(self, hero_uuid, uuids, cfg_hero.job)
    if not postbl then return {e = e} end

    local dirty_uuids, samemark = heqbag.puton(self, hero_uuid, uuids, postbl, {
        flag = "equip_puton_onekey",
        arg1 = hero_uuid,
        arg2 = table.concat(uuids or {}, "|")
    })
    hattrs.dirty(self, NM, table.unpack(dirty_uuids))

    for _, v in ipairs(samemark) do
        for mark, cnt in pairs(v) do
            task.trigger(self, "eqbody_stage_at" .. mark, cnt)
        end
    end

    return {e = 0}
end

function _H.equip_takeoff(self, msg)
    local hero_uuid, pos = msg.hero_uuid, msg.pos
    assert(hinit.query_cfg(self, hero_uuid))
    local onbody = query_eqbody(self, hero_uuid)
    if pos then
        if not onbody[pos] then return {e = 1} end
    else
        if not onbody then return {e = 1} end
    end

    heqbag.takeoff(self, hero_uuid, pos,
        {flag = "equip_takeoff", arg1 = hero_uuid, arg2 = pos})
    hattrs.dirty(self, NM, hero_uuid)
    return {e = 0}
end

function _H.equip_stageup(self, msg)
    local uuid = msg.uuid
    local eqdata = query_eqbag(self, uuid)
    local id = eqdata.id
    local owner = assert(eqdata.owner)
    local cfg = query_eqcfg(self, id)
    local new_id = cfg.advanced
    if not new_id then return {e = 1} end

    local option = {flag = "equip_stageup", arg1 = uuid, arg2 = new_id}
    if not award.del(self, option, {cfg.cost}) then return {e = 2} end

    heqbag.stageup(self, uuid, option)
    hattrs.dirty(self, NM, owner)
    return {e = 0, id = new_id}
end
