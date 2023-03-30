local skynet = require "skynet"
local client = require "client.mods"
local cfgproxy = require "cfg.proxy"
local flowlog = require "flowlog"
local chipbag = require "hero.chipbag"
local awardtype = require "role.award.type"
local hattrs = require "hero.attrs"
local passive = require "hero.passive"
local uaward = require "util.award"
local uattrs = require "util.attrs"
local cache = require("mongo.role")("chipbody")
local fnopen = require "role.fnopen"
local award = require "role.award"
local utable = require "util.table"
local schema = require "mongo.schema"
local hinit = require "hero"
local task = require "task"

local _H = require "handler.client"

local insert = table.insert
local mixture = utable.mixture
local maxinteger = math.maxinteger
local append_array = uattrs.append_array
local min = math.min
local chipcfg = chipbag.chipcfg

local NM<const> = "chip"
local HERO<const> = "hero"

cache.schema(schema.NOBJ(schema.NOBJ()))

local CFG, CFG_SUIT, CHIPBODY
skynet.init(function()
    CFG, CFG_SUIT = cfgproxy("chip", "chip_suit")
end)

local function chip_flowlog(self, opt, option, owner, id, pos, ...)
    local info = {
        opt = opt,
        flag = option.flag,
        arg1 = option.arg1,
        arg2 = option.arg2,
        owner = owner,
        id = id,
        pos = pos
    }
    local n = select("#", ...)
    for i = 1, n do
        local ars = select(i, ...)
        info["arg" .. (i + 2)] = ars
    end
    flowlog.role(self, "chipbody", info)
end

local function dirty(self, ...)
    hattrs.dirty(self, NM, ...)
    passive.dirty(self, NM, ...)
end

local function puton(self, owner, pos, id, option, old_owner)
    local body = CHIPBODY[owner]
    if not body then
        body = {}
        CHIPBODY[owner] = body
        hinit.query(self, owner).chips = body
    end
    body[pos] = id
    cache.dirty(self)
    chip_flowlog(self, "puton", option, owner, id, pos)
    return {id = id, pos = pos, owner = owner, old_owner = old_owner}
end

local function takeoff(self, owner, pos, option)
    local body = CHIPBODY[owner]
    local id = assert(body[pos])
    body[pos] = nil
    cache.dirty(self)

    if not next(body) then
        CHIPBODY[owner] = nil
        cache.dirty(self)
        hinit.query(self, owner).chips = nil
    end
    chip_flowlog(self, "takeoff", option, owner, id, pos)
    return {id = id, pos = pos, owner = owner}
end

local function takeoff_single(self, owner, pos, option)
    local chipinfo = takeoff(self, owner, pos, option)
    client.push(self, HERO, "chip_takeoff", {list = {chipinfo}})
    chipbag.add(self, {[chipinfo.id] = 1}, option)
end

local function takeoff_onbody(self, owner, option, pos)
    local body = CHIPBODY[owner]
    if not body then return end

    if pos then
        takeoff_single(self, owner, pos, option)
    else
        local cnts, push = {}, {}
        for _pos in pairs(body) do
            local chipinfo = takeoff(self, owner, _pos, option)
            insert(push, chipinfo)
            local id = chipinfo.id
            cnts[id] = (cnts[id] or 0) + 1
        end
        if not next(body) then
            CHIPBODY[owner] = nil
            cache.dirty(self)
            hinit.query(self, owner).chips = nil
        end
        chipbag.add(self, cnts, option)
        client.push(self, HERO, "chip_takeoff", {list = push})
    end
    dirty(self, owner)
end

require("hero.mod").reg {
    name = NM,
    load = function(self)
        CHIPBODY = cache.get(self)
    end,
    init = function(_, uuid, obj)
        obj.chips = CHIPBODY[uuid]
    end,
    reset = function(self, uuid, _, option)
        takeoff_onbody(self, uuid, option)
    end,
    remove = function(self, uuid, _, option)
        takeoff_onbody(self, uuid, option)
    end
}

hattrs.reg(NM, function(_, hero_uuid)
    local body = CHIPBODY[hero_uuid]
    local ret, suittab = {}, {}
    for _, id in pairs(body or {}) do
        local cfg = CFG[id]

        append_array(ret, cfg.attrs)

        local suit = cfg.suit
        local suitinfo = suittab[suit]
        if not suitinfo then
            suitinfo = {num = 0, quality = maxinteger}
            suittab[suit] = suitinfo
        end
        suitinfo.num = suitinfo.num + 1
        suitinfo.quality = min(suitinfo.quality, cfg.quality)
    end

    for suit, suitinfo in pairs(suittab) do
        local cfg_suit = CFG_SUIT[suit]
        for num, cfgsub in pairs(cfg_suit) do
            if suitinfo.num >= num then
                local _cfg = cfgsub[suitinfo.quality]
                if _cfg.attrs then append_array(ret, _cfg.attrs) end
            end
        end
    end
    return ret
end)

passive.reg(NM, function(_, hero_uuid)
    local body = CHIPBODY[hero_uuid]
    local effect, suittab = {}, {}
    for _, id in pairs(body or {}) do
        local cfg = CFG[id]
        local suit = cfg.suit
        local suitinfo = suittab[suit]
        if not suitinfo then
            suitinfo = {num = 0, quality = maxinteger}
            suittab[suit] = suitinfo
        end
        suitinfo.num = suitinfo.num + 1
        suitinfo.quality = min(suitinfo.quality, cfg.quality)
    end

    for suit, suitinfo in pairs(suittab) do
        local cfg_suit = CFG_SUIT[suit]
        for num, cfgsub in pairs(cfg_suit) do
            if suitinfo.num >= num then
                local _cfg = cfgsub[suitinfo.quality]
                if _cfg.effect then mixture(effect, _cfg.effect) end
            end
        end
    end
    return effect
end)

function _H.chip_puton(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end

    local uuid, tar_id, pos, ouuid = msg.uuid, msg.id, msg.pos, msg.oppo_uuid

    local cfg_chip = chipcfg(self, tar_id)
    assert(pos == cfg_chip.position)

    local body, oppo_body = CHIPBODY[uuid], nil
    local id, oppo_id

    if body then
        id = body[pos]
        if id == tar_id then return {e = 2} end
    end
    if ouuid then
        oppo_body = CHIPBODY[ouuid]
        oppo_id = oppo_body[pos]
        assert(tar_id == oppo_id)
    end

    local option = {flag = "chip_puton", arg1 = id, arg2 = oppo_id}
    local on_push, old_owner = {}, nil
    if id and oppo_id then
        insert(on_push, puton(self, ouuid, pos, id, option, uuid))
        dirty(self, ouuid)
        old_owner = ouuid
    elseif id then
        if chipbag.getcnt(self, tar_id) < 1 then return {e = 3} end
        chipbag.del(self, {[tar_id] = 1}, option)
        takeoff_single(self, uuid, pos, option)

    elseif oppo_id then
        client.push(self, HERO, "chip_takeoff",
            {list = {takeoff(self, ouuid, pos, option)}})
    else
        if chipbag.getcnt(self, tar_id) < 1 then return {e = 3} end
        chipbag.del(self, {[tar_id] = 1}, option)
    end

    insert(on_push, puton(self, uuid, pos, tar_id, option, old_owner))
    client.push(self, HERO, "chip_puton", {list = on_push})
    dirty(self, uuid)

    cache.dirty(self)
    return {e = 0}
end

local function check_full(self, body, pos)
    local total = 0
    if pos then
        total = 1
    else
        for _ in pairs(body) do total = total + 1 end
    end
    return chipbag.isfull(self, total)
end

function _H.chip_takeoff(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local uuid, pos = msg.uuid, msg.pos
    local body = CHIPBODY[uuid]
    if not body then return {e = 2} end
    if check_full(self, body, pos) then return {e = 3} end

    takeoff_onbody(self, uuid, {flag = "chip_takeoff", arg1 = uuid}, pos)
    return {e = 0}
end

local function stageup_check(self, list)
    local up, dels, adds, off, checkdel, checkpos, heroes = {}, {}, {}, {}, {},
        {}, {}
    for _, v in ipairs(list) do
        local target, costs = v.target, v.costs

        local id = assert(target.id)
        local cfg = chipcfg(self, id)
        local tar_id = cfg.advanced
        if not tar_id then return false, 3 end

        local cfg_cost = cfg.cost
        if cfg_cost[2] ~= #costs then return false, 4 end

        local owner = target.owner
        if owner then
            local body = CHIPBODY[owner]
            local pos = assert(target.pos)
            assert(id == body[pos])
            local mark = string.format("%d_%d", owner, pos)
            if checkpos[mark] then return false, 5 end
            checkpos[mark] = true
            insert(up, {owner = owner, id = tar_id, pos = pos, old_id = id})
            insert(heroes, owner)
        else
            -- 成对加减不用检查包包上限
            checkdel[id] = (checkdel[id] or 0) + 1
            dels[id] = (dels[id] or 0) + 1
            adds[tar_id] = (adds[tar_id] or 0) + 1
        end

        local cfg_id = cfg_cost[1]
        for _, i in ipairs(costs) do
            local cost_id, cost_owner = assert(i.id), i.owner
            if cost_id ~= cfg_id then return false, 6 end
            if cost_owner then
                local body = CHIPBODY[cost_owner]
                local cost_pos = assert(i.pos)
                assert(cost_id == body[cost_pos])

                local mark = string.format("%d_%d", cost_owner, cost_pos)
                if checkpos[mark] then return false, 7 end
                checkpos[mark] = true

                insert(off, {owner = cost_owner, pos = cost_pos})
                insert(heroes, cost_owner)
            else
                checkdel[cost_id] = (checkdel[cost_id] or 0) + 1
                dels[cost_id] = (dels[cost_id] or 0) + 1
            end
        end
    end
    if next(checkdel) and not chipbag.checkdel(self, checkdel) then
        return false, 8
    end
    return up, dels, adds, off, heroes
end

local function stageup_execute(self, option, up, dels, adds, off, heroes)
    if next(off) then
        local push = {}
        for _, v in ipairs(off) do
            insert(push, takeoff(self, v.owner, v.pos, option))
        end
        client.push(self, HERO, "chip_takeoff", {list = push})
    end

    chipbag.del(self, dels, option)

    if next(adds) then chipbag.add(self, adds, option) end

    for _, v in ipairs(up) do
        local body = CHIPBODY[v.owner]
        body[v.pos] = v.id
        chip_flowlog(self, "stageup", option, v.owner, v.old_id, v.pos, v.id)
    end
    client.push(self, HERO, "chip_stage", {list = up})

    cache.dirty(self)
    dirty(self, table.unpack(heroes))
    return true
end

local function stage(self, list, option)
    if not fnopen.check_open(self, NM) then return {e = 1} end

    if not next(list) then return {e = 2} end
    local up, dels, adds, off, heroes = stageup_check(self, list)
    if not up then return {e = dels} end
    stageup_execute(self, option, up, dels, adds, off, heroes)

    local cnt = #list
    task.trigger(self, "chip_stageup", cnt)
    option.arg1 = cnt
    flowlog.role_act(self, option)
    return {e = 0}
end

function _H.chip_stageup(self, msg)
    return stage(self, {msg.chip}, {flag = "chip_stageup"})
end

function _H.chip_stageup_onekey(self, msg)
    return stage(self, msg.list, {flag = "chip_stageup_onekey"})
end

function _H.chip_resolve(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end

    local dels, ua = {}, uaward()
    for id, cnt in pairs(msg.list) do
        if chipbag.getcnt(self, id) < cnt then return {e = 2} end

        local resolve = chipcfg(self, id).resolve
        ua.append_one({resolve[1], resolve[2], resolve[3] * cnt})
        insert(dels, {awardtype.chip, id, cnt})
    end

    local option = {flag = "chip_resolve"}
    local ok, err = award.deladd(self, option, dels, ua.result)
    if not ok then return {e = err} end

    flowlog.role_act(self, option)
    return {e = 0}
end
