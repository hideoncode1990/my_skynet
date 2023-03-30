local skynet = require "skynet"
local net = require "robot.net"
local json = require "rapidjson.c"
local httpc = require "http.httpc"

local setting = require("setting.factory").proxy("robot")
local uurl = require("util.url")
local timer = require "timer"
local _H = require "handler.client"

local log = require "robot.log"

local waiting, co
function _H.pay_success(self)
    waiting = nil
    if co then skynet.wakeup(co) end
end

local function pay_order(self, goods)
    local ret = assert(net.request(self, 100, "pay_order", {
        goodsid = goods.goodsid,
        info = json.encode {}
    }))
    if ret.e ~= 0 then
        log(self, {opt = "pay", goodsid = goods.goodsid, e = ret.e})
        return
    end

    waiting = true
    ret.info = json.decode(ret.info)
    return ret
end

local function pay(self, goods)
    local order = pay_order(self, goods)
    if not order then return end

    local recv_header, header = {}, {
        ["Content-Type"] = "application/json;charset=UTF-8"
    }

    local host, path = uurl.parse(setting.recharge)

    local ok, code, body = pcall(httpc.request, "POST", host, path, recv_header,
        header, json.encode {
            uid = order.info.uid3rd,
            orderid = order.order,
            amount = order.info.money
        })
    assert(ok, tostring(code))

    assert(code == 200, code)
    local ret = json.decode(body)
    if ret.e == 0 then
        log(self, {opt = "pay", e = 0, goodsid = goods.goodsid})
        return true
    else
        log(self, {opt = "pay", goodsid = goods.goodsid, err = ret.m or ret.e})
    end

end

local function wait()
    assert(co == nil)
    co = coroutine.running()
    local tid = timer.add(3000, function()
        skynet.wakeup(co)
        co = false
    end)
    skynet.wait(co)
    assert(co, "testcast.pay waiting timeout")
    co = nil
    timer.del(tid)
end

return {
    onlogin = function(self)
        if waiting then wait() end
        local recharge = net.request(self, 100, "pay_list")
        local list = {}
        for _, d in pairs(recharge.list) do table.insert(list, d) end
        assert(#list > 0)
        pay(self, list[math.random(1, #list)])
    end
}
