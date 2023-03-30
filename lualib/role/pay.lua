local awardtype = require "role.award.type"
local skynet = require "skynet"
local flowlog = require "flowlog"
local event = require "role.event"
local client = require "client"
local award = require "role.award"
local env = require "env"
local uaward = require "util.award"

local _LUA = require "handler.lua"
local _H = require "handler.client"

local cache = require("mongo.role")("pay")

local payd
skynet.init(function()
    payd = skynet.uniqueservice("game/payd")
end)

require("role.mods") {name = "m_pay", load = cache.get}

local METHOD = {}

local _M = {}
function _M.check_award(info, buytimes)
    local ctx = uaward()
    local worth_game = info.worth_game or 0
    local worth_gift = info.worth_gift or 0
    if buytimes then
        local worth_giftfirst = info.worth_giftfirst or 0
        if buytimes == 0 and worth_giftfirst > 0 then
            worth_gift = worth_giftfirst
        end
    end
    if worth_game > 0 or worth_gift > 0 then
        ctx.append_one({awardtype.diamond, worth_game, worth_gift})
        info.value_quantity = worth_game + worth_gift
    else
        info.value_quantity = 0
    end

    local vipexp = info.vipexp
    if vipexp > 0 then ctx.append_one({awardtype.vip_exp, 0, vipexp}) end
    return ctx
end

function _M.finish(self, info)
    local mainid = info.mainid
    local order = info.order
    local order3rd = info.order3rd
    local goodsid = info.goodsid
    local money = info.money
    local type = info.type
    local value_quantity = info.value_quantity

    local BUYC = cache.getsub(self, "buytimes")
    local ORDERC = cache.getsub(self, "order")
    BUYC[mainid], ORDERC[order] = (BUYC[mainid] or 0) + 1, mainid
    cache.dirty(self)
    flowlog.platlog(self, "paylog", {
        order = order,
        order3rd = order3rd,
        type = type,
        goodsid = goodsid,
        mainid = mainid,
        money = money,
        viplevel = self.viplevel
    }, "recharge", {
        grade_id = "null",
        value_quantity = value_quantity,
        currency = "1",
        value_amount = award.getcnt(self, awardtype.diamond) + value_quantity
    })
    return true
end

function _LUA.pay_notice(self, info)
    local order = info.order
    local type = info.type

    local ORDERC = cache.getsub(self, "order")
    if ORDERC[order] then return true end

    local class = METHOD[type]
    if not class then return false, "method error " .. tostring(type) end

    local ok, ret = class.pay(self, info)
    if not ok then return false, ret end

    event.occur("EV_PAY", self, info)
    client.push(self, "pay_success", {goodsid = info.goodsid, order = order})
    return true
end

local paylist
function _H.pay_list(self)
    local ok, list = skynet.call(payd, "lua", "pay_list",
        {rid = self.rid, channel = self.channel})
    if ok then
        for _, info in pairs(list) do
            local class = METHOD[info.type]
            if class and class.init then class.init(self, info) end
        end
        paylist = list
        return {e = 0, list = list}
    else
        return {e = 1}
    end
end
--[[
{
    --gamecenter
    10000 账号不存在

    --payd
    11 商品不存在

    --m_gift
    101 礼包超过数量限制

    --m_yueka
    102 月卡超过数量限制
    
    --m_battlepass
    103 该周期已经购买
    104 在该周期保护时间内，无法购买
}
--]]
function _H.pay_order(self, msg)
    if env.disable_pay == "true" then return {e = 99} end

    local goodsid = msg.goodsid
    local role = {
        rid = tostring(self.rid),
        rname = self.rname,
        uid = self.uid,
        sid = self.sid,
        channel = self.channel,
        ip = self.ip,
        level = self.level
    }
    for _, info in pairs(paylist) do
        local class = METHOD[info.type]
        if info.goodsid == goodsid then
            if class.check then
                local ok, err = class.check(self, info)
                if not ok then return {e = err} end
            end
            local ok, order, clientinfo =
                skynet.call(payd, "lua", "pay_order", role, goodsid, msg.info)
            if not ok then
                return {e = order}
            else
                return {e = 0, order = order, info = clientinfo}
            end
        end
    end
    return {e = 1}
end

function _M.reg(mod, name)
    local nm = assert(name or mod.name)
    METHOD[nm] = mod
end

return _M
