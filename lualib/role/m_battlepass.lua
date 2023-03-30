local skynet = require "skynet"
local client = require "client.mods"
local cache = require("mongo.role")("battlepass")
local flowlog = require "flowlog"
local utime = require "util.time"
local cfgproxy = require "cfg.proxy"
local award = require "role.award"
local event = require "role.event"
local email = require "email"
local lang = require "lang"
local awardtype = require "role.award.type"
local variable = require "variable"
local schema = require "mongo.schema"
local ubit = require "util.bit"
local uaward = require "util.award"
local utable = require "util.table"
local pay = require "role.pay"
local fnopen = require "role.fnopen"

local _H = require "handler.client"

cache.schema(schema.NOBJ())

local NM<const>, DAYSEC<const> = "battlepass", 86400

local TYPE = {"normal", "high"}

local CFG, CFG_REWARD, CFG_MAINID
skynet.init(function()
    CFG, CFG_REWARD, CFG_MAINID = cfgproxy("battlepass", "battlepass_reward",
        "battlepass_mainid")
end)

local function new_data(self, C, id, time, group)
    local old_d = C[id]
    local d = {
        update = time,
        id = id,
        level = 1,
        exp = 0,
        group = group,
        normal = {},
        high = {}
    }
    C[id] = d
    cache.dirty(self)

    flowlog.role(self, NM, {
        flag = "data_init",
        arg1 = d.group,
        opt = "init",
        id = id,
        level_prev = old_d and old_d.level or d.level,
        level = 1,
        exp_prev = old_d and old_d.exp or d.exp,
        exp = 0
    })
    return d
end

local function del_data(self, C, id, d)
    C[id] = nil
    cache.dirty(self)

    flowlog.role(self, NM, {
        flag = "data_del",
        arg1 = d.group,
        opt = "del",
        id = id,
        level_prev = d.level,
        level = 1,
        exp_prev = d.exp,
        exp = 0
    })
end

local function get_data(self, C, id)
    return C[id] or new_data(self, C, id, utime.time_int(), CFG[id].group)
end

local function get_cfglv(_, d)
    local group = d.group
    return CFG_REWARD[group]
end

local function calc(self, id, d, add, nms, pkts, option)
    local level_prev, exp_prev = d.level, d.exp
    local level, exp = level_prev, exp_prev + add
    local cfglv = get_cfglv(self, d)
    local cfg = cfglv[level]
    while true do
        local expmax = cfg.exp
        if exp >= expmax then
            cfg = cfglv[level + 1]
            if not cfg then break end

            level = level + 1
            exp = exp - expmax
        else
            break
        end
    end
    if level_prev ~= level or exp ~= exp_prev then
        d.level, d.exp = level, exp
        cache.dirty(self)
        if level > 0 and exp > 0 then
            flowlog.role(self, NM, {
                flag = option.flag,
                arg1 = option.arg1,
                arg2 = option.arg2,
                opt = "add",
                id = id,
                level_prev = level_prev or 0,
                level = level,
                exp_prev = exp_prev,
                exp = exp,
                addexp = add
            })
        end
        if pkts then
            nms.battlepass_add = NM
            table.insert(pkts.battlepass_add,
                {id = id, level = d.level, exp = d.exp})
        end
    end
end

award.reg {
    type = awardtype.battlepass,
    add = function(self, nms, pkts, option, items)
        local exps = {}
        for _, item in ipairs(items) do
            local id, exp = item[2], item[3]
            assert(CFG[id] and exp > 0)
            exps[id] = (exps[id] or 0) + exp
        end
        local C = cache.get(self)
        for id, exp in pairs(exps) do
            local d = get_data(self, C, id)
            calc(self, id, d, exp, nms, pkts, option)
        end
        return true
    end
}

-- agent加载数据时，如果id在CFG表里不存在 或 该id的group在CFG_REWARD不存在
-- 就关闭该活动，清除数据
local function check_error_data(self)
    local C = cache.get(self)
    for id, d in pairs(C) do
        if not CFG[id] or not CFG_REWARD[d.group] then
            del_data(self, C, id, d)
        end
    end
end

local function same_period(self, reset, now, update)
    local start = utime.begin_day(variable["starttime_" .. self.sid])
    local sec = reset * DAYSEC
    local now_period = (now - start) // sec + 1
    local overti = start + now_period * sec
    if update then
        local update_period = (update - start) // sec + 1
        return update_period == now_period, overti
    else
        return true, overti
    end
end

local function in_protect_period(self, id)
    local now = utime.time_int()
    local cfg = CFG[id]
    local reset, protect = cfg.reset, cfg.protect

    local _, overti = same_period(self, reset, now)
    local startti = overti - protect
    return now >= startti and now < overti
end

local function get_all(self, C, id)
    local reward = uaward()
    local d = get_data(self, C, id)
    local cfglv = get_cfglv(self, d)
    local change
    local get = {}

    for tpid, tpnm in ipairs(TYPE) do
        if tpid == 2 and not d.bought then break end
        local data = d[tpnm]
        local subget = utable.getsub(get, tpnm)
        for i = 1, d.level do
            if not ubit.get(data, i) then
                reward.append(cfglv[i][tpnm])
                table.insert(subget, i)
                change = true
            end
        end
    end
    return change, reward, d, get
end

local function check_update(self)
    local C = cache.get(self)
    local now = utime.time_int()
    for id, cfg in pairs(CFG) do
        local d = C[id]
        local same, overti
        if d then
            same, overti = same_period(self, cfg.reset, now, d.update)
            if not same then
                local change, reward = get_all(self, C, id)
                if change then
                    email.send {
                        target = self.rid,
                        theme = lang("BATTLEPASS_THEME_" .. id),
                        content = lang("BATTLEPASS_CONTENT_" .. id),
                        items = reward.result,
                        option = {flag = "battlepass_period_over"}
                    }
                end
                d = new_data(self, C, id, now, cfg.group)
            end
        else
            _, overti = same_period(self, cfg.reset, now)
            d = new_data(self, C, id, now, cfg.group)
        end
        d.overti = overti
    end
    return C
end

local function battlepass_info(self)
    client.enter(self, NM, "battlepass_info", {info = check_update(self)})
end

require "role.mods" {
    name = NM,
    load = check_error_data,
    enter = battlepass_info
}

local NMACT<const> = "battlepassact"
function _H.battlepass_get(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end

    local id, tpid, level = msg.id, msg.type, msg.level
    local tpnm = TYPE[tpid]
    assert(CFG[id] and tpnm)

    local d = get_data(self, cache.get(self), id)
    local cfglv = get_cfglv(self, d)
    local cfg = assert(cfglv[level])

    local levelmax = d.level
    if level > levelmax then return {e = 2} end
    if tpid == 2 and not d.bought then return {e = 3} end

    local data = d[tpnm]
    if ubit.get(data, level) then return {e = 4} end

    local option = {flag = "battlepass_get", arg1 = id, arg2 = tpnm .. level}
    local ok, err = award.add(self, option, cfg[tpnm])
    if not ok then return {e = err} end

    ubit.set(data, level)
    cache.dirty(self)
    flowlog.role(self, NMACT, {
        flag = "get",
        id = id,
        type = tpnm,
        levelget = level,
        levelmax = levelmax
    })
    return {e = 0}
end

function _H.battlepass_get_onekey(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end

    local id = msg.id
    local change, reward, d, get = get_all(self, cache.get(self), id)

    if not change then return {e = 2} end

    local option = {flag = "battlepass_get_onekey", arg1 = id}
    local ok, err = award.add(self, option, reward.result)
    if not ok then return {e = err} end

    for tpnm, subget in pairs(get) do
        local data = d[tpnm]
        for _, level in ipairs(subget) do ubit.set(data, level) end
    end
    cache.dirty(self)

    flowlog.role(self, NMACT, {flag = "get_onekey", id = id, levelmax = d.level})
    return {e = 0, normal = get.normal, high = get.high}
end

function _H.battlepass_buy_level(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end

    local id, tarlv = msg.id, msg.level
    local d = get_data(self, cache.get(self), id)
    local cfglv = get_cfglv(self, d)
    assert(cfglv[tarlv])

    local level = d.level
    if tarlv <= level then return {e = 2} end

    local exp = -d.exp
    for i = level, tarlv - 1 do exp = exp + cfglv[i].exp end
    assert(exp > 0)

    local cfg = CFG[id]
    local cfg_cost = cfg.cost
    local cost = math.ceil(exp * cfg.exchange)
    cost = {{cfg_cost[1], cfg_cost[2], cost}}

    local ok, err = award.deladd(self, {
        flag = "battlepass_buy_level",
        arg1 = id,
        arg2 = tarlv
    }, cost, {{awardtype.battlepass, id, exp}})
    if not ok then return {e = err} end

    flowlog.role(self, NMACT, {
        flag = "buy_level",
        id = id,
        levelbefore = level,
        levelmax = tarlv
    })
    return {e = 0}
end

pay.reg {
    name = NM,
    check = function(self, info)
        local id = CFG_MAINID[info.mainid]
        local d = get_data(self, cache.get(self), id)
        if d.bought then return false, 103 end
        if in_protect_period(self, id) then return false, 104 end

        return true
    end,
    pay = function(self, info)
        local id = CFG_MAINID[info.mainid]
        local d = get_data(self, cache.get(self), id)
        if d.bought then return false end

        local ctx = pay.check_award(info)
        ctx.append(CFG[id].reward)
        pay.finish(self, info)
        d.bought = 1
        cache.dirty(self)

        award.adde(self, {
            flag = "battlepass_buy_high",
            arg1 = id,
            theme = "BATTLEPASS_BUY_FULL_THEME",
            content = "BATTLEPASS_BUY_FULL_CONTENT"
        }, ctx.result)
        client.push(self, NM, "battlepass_buy_high",
            {id = id, bought = d.bought})
        return true
    end
}

event.reg("EV_UPDATE", NM, battlepass_info)
