local cache = require("mongo.role")("gift")
local cfgproxy = require "cfg.proxy"
local utime = require "util.time"
local pay = require "role.pay"
local award = require "role.award"
local client = require "client"
local uaward = require "util.award"
local _H = require "handler.client"

local CFGS
require("skynet").init(function()
    CFGS = cfgproxy("pay_gift")
end)

local CHECKS = {
    [1] = utime.same_day,
    [2] = utime.same_week,
    [3] = utime.same_month
}

local function pushinfo(self)
    local info = {}
    local now = utime.time_int()
    for mainid, C in pairs(cache.get(self)) do
        local cfg = CFGS[mainid]
        if cfg then
            local limit, freshtype = cfg.limit, cfg.freshtype
            if limit then
                if CHECKS[freshtype](C.ti or 0, now) then
                    info[mainid] = C
                end
            end
        end
    end
    client.push(self, "pay_gift_info", {info = info})
end

local function checkbuy(mainid, C, now)
    local cfg = CFGS[mainid]
    local limit, freshtype = cfg.limit, cfg.freshtype

    local cnt = C.cnt or 0
    if limit then
        if not CHECKS[freshtype](C.ti or 0, now) then cnt = 0 end
        if cnt >= limit then return false, 101 end
    end
    return true, cfg, cnt
end

pay.reg {
    name = "gift",
    check = function(self, info)
        local mainid = info.mainid
        local now = utime.time_int()
        return checkbuy(mainid, cache.getsub(self, mainid), now)
    end,
    pay = function(self, info)
        local mainid = info.mainid

        local now = utime.time_int()
        local C = cache.getsub(self, mainid)
        local ok, cfg, cnt = checkbuy(mainid, C, now)
        if not ok then return false, "buymax" end

        local ctx = pay.check_award(info)
        ctx.append(cfg.items)
        pay.finish(self, info)

        C.cnt, C.ti = cnt + 1, now
        cache.dirty(self)
        assert(award.add(self, {flag = "pay_gift", arg1 = info.order},
            ctx.result))

        pushinfo(self)
        return true
    end
}

require("role.mods") {name = "gift", enter = pushinfo}

function _H.gift_buyfree(self, msg)
    local mainid = msg.mainid
    local now = utime.time_int()
    local C = cache.getsub(self, mainid)
    local ok, cfg, cnt = checkbuy(mainid, C, now)
    if not ok then return {e = 1} end

    C.cnt, C.ti = cnt + 1, now
    cache.dirty(self)
    assert(award.add(self, {flag = "gift_buyfree", arg1 = mainid},
        uaward(cfg.items).result))

    pushinfo(self)
    return {e = 0}
end
