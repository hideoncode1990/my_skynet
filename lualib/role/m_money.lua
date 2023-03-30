local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local client = require "client.mods"
local award = require "role.award"
local money_types = require "role.award.money"
local cache = require("mongo.role")("money")
local flowlog = require "flowlog"

local NM<const> = "money"

local CFG
skynet.init(function()
    CFG = cfgproxy("money")
end)

local min = math.min

require("role.mods") {
    name = NM,
    load = cache.get,
    enter = function(self)
        local C = cache.get(self)
        local types, cnts = {}, {}
        for tp, _ in pairs(money_types) do
            local cnt = C[tostring(tp)] or 0
            table.insert(types, tp)
            table.insert(cnts, cnt)
        end
        client.enter(self, NM, "money_all", {types = types, cnts = cnts})
    end
}

local function calc_add(tp, prev, cnt)
    local cfg = CFG[tp]
    if not cfg then return cnt end

    local max = cfg.max
    if not max then return cnt end

    local rest = max - prev
    return rest > 0 and min(rest, cnt) or 0
end

local function money_add(self, nms, pkts, tp, items, option)
    local cnt = 0
    nms.money_add = NM
    for _, cfg in ipairs(items) do
        local c = cfg[3]
        cnt = (cnt or 0) + c
    end

    assert(cnt > 0)

    local C = cache.get(self)
    local tp_str = tostring(tp)
    local prev = C[tp_str] or 0
    local change = calc_add(tp, prev, cnt)
    if change <= 0 then return true end

    local last = prev + change
    C[tp_str] = last
    cache.dirty(self)
    flowlog.platlog(self, "money", {
        money = money_types[tp],
        opt = "add",
        flag = option.flag,
        arg1 = option.arg1,
        arg2 = option.arg2,
        prev = prev,
        last = last,
        change = cnt
    }, "money", {tp = tp, action = 1})
    table.insert(pkts.money_add, {change = change, last = last, type = tp})
    return true
end

local function money_del(self, nms, pkts, tp, items, option)
    local cnt = 0
    nms.money_del = NM
    for _, cfg in ipairs(items) do
        local c = cfg[3]
        cnt = (cnt or 0) + c
    end

    assert(cnt > 0)
    local C = cache.get(self)
    local tp_str = tostring(tp)
    local prev = C[tp_str] or 0
    local last = prev - cnt
    if last < 0 then return false end
    C[tp_str] = last
    cache.dirty(self)

    flowlog.platlog(self, "money", {
        money = money_types[tp],
        opt = "del",
        flag = option.flag,
        arg1 = option.arg1,
        arg2 = option.arg2,
        prev = prev,
        last = last,
        change = cnt
    }, "money", {action = -1, tp = tp})
    table.insert(pkts.money_del, {change = -cnt, last = last, type = tp})
    return true
end

local function money_checkdel(self, tp, items)
    local cnt = 0
    for _, cfg in ipairs(items) do
        local c = cfg[3]
        cnt = (cnt or 0) + c
    end

    return (cache.get(self)[tostring(tp)] or 0) >= cnt
end

local function money_getcnt(self, tp)
    return cache.get(self)[tostring(tp)] or 0
end

for tp in pairs(money_types) do
    award.reg {
        type = tp,
        add = function(self, nms, pkts, option, item)
            return money_add(self, nms, pkts, tp, item, option)
        end,
        del = function(self, nms, pkts, option, item)
            return money_del(self, nms, pkts, tp, item, option)
        end,
        checkdel = function(self, item)
            return money_checkdel(self, tp, item)
        end,
        getcnt = function(self)
            return money_getcnt(self, tp)
        end
    }
end
