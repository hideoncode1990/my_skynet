local cfgproxy = require "cfg.proxy"
local client = require "client"
local utime = require "util.time"
local pay = require "role.pay"
local award = require "role.award"
local email = require "email"
local vip = require "role.m_vip"
local lang = require "lang"
local schema = require "mongo.schema"
local event = require "role.event"
local cache = require("mongo.role")("yueka")

local _H = require "handler.client"

cache.schema(schema.OBJ {counts = schema.ORI, cards = schema.NOBJ()})

local CFGS, CFG_ADDITION, CFG_DAILY
require("skynet").init(function()
    CFGS, CFG_ADDITION, CFG_DAILY = cfgproxy("pay_yueka", "pay_privilege",
        "pay_yuekadaily")
end)

local function update_daily(self, type)
    local C = cache.getsub(self, "cards")
    local card = C[type]
    if not card then return end

    local cfgs = CFG_DAILY[type]
    if not cfgs then return end

    local now = utime.time_int()
    local over, daily = card.over, card.daily

    local maxeti = utime.begin_day(math.min(over, now))
    local eti = math.floor(daily) + 24 * 60 * 60

    local viplvl = vip.get(self)
    while true do
        if not utime.same_day(eti, maxeti) and eti < maxeti then
            local items = cfgs[viplvl]
            if items then
                email.send {
                    target = self.rid,
                    theme = lang("YUEKA_DAILY_AWARD_THEME_{1}",
                        os.date("%Y-%m-%d", eti)),
                    content = lang("YUEKA_DAILY_AWARD_CONTENT"),
                    items = items,
                    option = {flag = "yueka_daily", arg1 = viplvl}
                }
            end
            card.daily = eti
            cache.dirty(self)
            eti = eti + 24 * 60 * 60
        else
            break
        end
    end

    if now >= over then
        C[type] = nil
        cache.dirty(self)

        local items = cfgs[viplvl]
        if items then
            email.send {
                target = self.rid,
                theme = lang("YUEKA_DAILY_AWARD_THEME_{1}",
                    os.date("%Y-%m-%d", over)),
                content = lang("YUEKA_DAILY_AWARD_CONTENT"),
                items = items,
                option = {flag = "yueka_daily", arg1 = viplvl}
            }
        end
        email.send {
            target = self.rid,
            theme = lang("YUEKA_OVER_THEME_{1}", os.date("%Y-%m-%d", over)),
            content = lang("YUEKA_OVER_CONTENT"),
            option = {flag = "yueka_over"}
        }
    end
end

pay.reg {
    name = "yueka",
    check = function(self, info)
        local mainid = info.mainid
        local cnt = cache.getsub(self, "counts")[mainid] or 0
        local limit = CFGS[mainid].limit
        if limit and cnt >= limit then return false, 102 end
        return true, cnt
    end,
    pay = function(self, info)
        local mainid = info.mainid
        local cfg = CFGS[mainid]

        local counts = cache.getsub(self, "counts")
        local cards = cache.getsub(self, "cards")

        local limit = cfg.limit
        local cnt = counts[mainid] or 0
        if limit then if cnt >= limit then return false, "buymax" end end

        update_daily(self, type)

        local type = cfg.type
        local ctx = pay.check_award(info)

        pay.finish(self, info)

        local tiadd = cfg.time * 24 * 60 * 60
        local firstgive = cfg.firstgive
        if cnt == 0 and firstgive then tiadd = tiadd + firstgive end

        counts[mainid] = cnt + 1

        local card = cards[type]
        if card then
            card.over = card.over + tiadd
        else
            cards[type] = {
                over = utime.time_int() + tiadd,
                daily = utime.begin_day(utime.time()) - 1
            }
        end
        cache.dirty(self)

        assert(award.add(self, {flag = "pay_yueka", arg1 = info.order},
            ctx.result))
        client.push(self, "pay_yueka_info", {counts = counts, cards = cards})
        return true
    end
}

local privilege_type<const> = 3
require("role.addition").reg("yueka", function(self, key)
    local card = cache.getsub(self, "cards")[privilege_type]
    if not card then return end
    local ti = card.over
    if utime.time() < ti then return CFG_ADDITION[key] end
end)

require("role.mods") {
    name = "yueka",
    load = function(self)
        local C = cache.getsub(self, "cards")
        for type in pairs(C) do update_daily(self, type) end
    end,
    enter = function(self)
        local C = cache.get(self)
        client.push(self, "pay_yueka_info", {counts = C.counts, cards = C.cards})
    end
}

function _H.yueka_daily(self, msg)
    local type = msg.type
    local cfgs = assert(CFG_DAILY[type])
    if not cfgs then return {e = 0} end

    update_daily(self, type)
    local card = cache.getsub(self, "cards")[type]
    if not card then return {e = 2} end

    local items = cfgs[vip.get(self)]
    if not items then return {e = 3} end

    local now = utime.time_int()

    assert(utime.same_day(card.daily, utime.begin_day(now) - 1))

    card.daily = now
    cache.dirty(self)
    assert(award.add(self, {flag = "yueka_daily"}, items))

    local C = cache.getsub(self)
    client.push(self, "pay_yueka_info", {counts = C.counts, cards = C.cards})
    return {e = 0}
end

event.reg("EV_UPDATE", "yueka", function(self)
    for type in pairs(cache.getsub(self, "cards")) do
        update_daily(self, type)
    end
end)
