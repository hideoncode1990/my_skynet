local client = require "client.mods"
local cache = require("mongo.role")("diamond")
local flowlog = require "flowlog"
local award = require "role.award"
local pay = require "role.pay"
local awardtype = require "role.award.type"

local _M = {}
local NM<const> = "diamond"

require "role.mods" {
    name = NM,
    load = function(self)
        local C = cache.get(self)
        C.bind = C.bind or 0
        C.bindcoin = C.bindcoin or 0
    end,
    enter = function(self)
        local C = cache.get(self)
        client.enter(self, NM, "diamond_info",
            {bind = (C.bind or 0) + (C.bindcoin or 0)})
    end
}

local function add(self, bind, bindcoin, nms, pkts, option)
    local C = cache.get(self)
    nms.diamond_add = NM
    local bind_prev, bindcoin_prev = C.bind or 0, C.bindcoin or 0
    local bind_last, bindcoin_last = C.bind + bind, C.bindcoin + bindcoin
    C.bind, C.bindcoin = bind_last, bindcoin_last
    cache.dirty(self)

    flowlog.platlog(self, NM, {
        flag = option.flag,
        arg1 = option.arg1,
        arg2 = option.arg2,
        bind_last = bind_last,
        bind_prev = bind_prev,
        bind = bind or 0,
        bindcoin_last = bindcoin_last,
        bindcoin_prev = bindcoin_prev,
        bindcoin = bindcoin or 0,
        opt = "add"
    }, "money", {
        tp = awardtype.diamond,
        flag = option.flag,
        action = 1,
        change = bind + bindcoin,
        last = bind_last + bindcoin_last
    })
    table.insert(pkts.diamond_add,
        {change = bind + bindcoin, last = bind_last + bindcoin_last})
    return bind_last, bindcoin_last
end

local function del(self, cost, nms, pkts, option)
    local C = cache.get(self)
    nms.diamond_del = NM
    local bind_prev, bindcoin_prev = C.bind or 0, C.bindcoin or 0

    local bind_cost = math.min(bind_prev, cost)
    local bind_last = bind_prev - bind_cost
    local bindcoin_cost = cost - bind_cost
    local bindcoin_last = bindcoin_prev - bindcoin_cost
    if bindcoin_last < 0 then return false end

    C.bind, C.bindcoin = bind_last, bindcoin_last
    cache.dirty(self)

    flowlog.platlog(self, "diamond", {
        flag = option.flag,
        arg1 = option.arg1,
        arg2 = option.arg2,
        bind_last = bind_last,
        bind_prev = bind_prev,
        bind = bind_cost or 0,
        bindcoin_last = bindcoin_last,
        bindcoin_prev = bindcoin_prev,
        bindcoin = bindcoin_cost or 0,
        opt = "del"
    }, "money", {
        tp = awardtype.diamond,
        flag = option.flag,
        action = -1,
        change = cost,
        last = bind_last + bindcoin_last
    })
    table.insert(pkts.diamond_del,
        {change = cost, last = bind_last + bindcoin_last})
    return true
end

local function checkdel(self, bindcoin)
    if bindcoin == 0 then return true end
    local C = cache.get(self)
    return bindcoin <= (C.bindcoin or 0) + (C.bind or 0)
end

award.reg {
    type = awardtype.diamond,
    add = function(self, nms, pkts, option, items)
        local bind, bindcoin = 0, 0
        for _, item in ipairs(items) do
            bind = bind + (item[2] or 0)
            bindcoin = bindcoin + (item[3] or 0)
        end
        return add(self, bind, bindcoin, nms, pkts, option)
    end,
    del = function(self, nms, pkts, option, items)
        local bindcoin = 0
        for _, item in ipairs(items) do
            bindcoin = bindcoin + (item[3] or 0)
        end
        return del(self, bindcoin, nms, pkts, option)
    end,
    checkdel = function(self, items)
        local bindcoin = 0
        for _, item in ipairs(items) do
            bindcoin = bindcoin + (item[3] or 0)
        end
        return checkdel(self, bindcoin)
    end,
    getcnt = function(self)
        local C = cache.get(self)
        local bindcoin, bind = C.bindcoin or 0, C.bind or 0
        return bindcoin + bind
    end
}

pay.reg {
    name = NM,
    init = function(self, info)
        local mainid = info.mainid
        local cnt = cache.getsub(self, "counts")[mainid] or 0
        if cnt == 0 then
            local worth_giftfirst = info.worth_giftfirst
            if worth_giftfirst > 0 then
                info.worth_gift = 0 - worth_giftfirst
            end
        end
    end,
    pay = function(self, info)
        local mainid = info.mainid
        local COUNTS = cache.getsub(self, "counts")

        local cnt = COUNTS[mainid] or 0
        local ctx = pay.check_award(info, cnt)

        pay.finish(self, info)

        COUNTS[mainid] = cnt + 1
        cache.dirty(self)

        assert(award.add(self, {flag = "pay_diamond", arg1 = info.order},
            ctx.result))
        return true
    end
}

return _M
