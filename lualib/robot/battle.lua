local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local fnopen = require "robot.fnopen"
local net = require "robot.net"
local _H = require "handler.client"
local timer = require "timer"

local OVERTIME<const> = 1000 * 100

local BASIC
skynet.init(function()
    BASIC = cfgproxy("basic")
end)

local _M = {}

local CTX, OK, MSG
function _M.wait(self, ctx)
    assert(not CTX)
    CTX = ctx
    timer.add(OVERTIME, function()
        if CTX == ctx then
            CTX = nil
            MSG = {false, "timeout"}
            skynet.wakeup(ctx)
        end
    end)
    if not CTX.skip then net.request(self, nil, "battle_real_start", {}) end

    skynet.wait(ctx)

    local ok, msg = OK, MSG
    OK, MSG = nil, nil

    assert(ok, msg)
    return ok, msg
end

function _M.over(self, ok, msg)
    local ctx = assert(CTX)
    CTX = nil
    OK = ok
    MSG = msg
    skynet.wakeup(ctx)
end

function _H.battle_end(self, msg)
    -- 机器人不会重开或者终结战斗，如果wrong为真，表示错误战斗
    local wrong = msg.restart and msg.terminate
    if wrong then
        _M.over(self, false, "wrong")
    else
        _M.over(self, true, msg)
    end
end

function _M.get_accelerate(self)
    local cfg = BASIC.multspeed
    local lv = 1
    for i = #cfg, 1, -1 do
        if fnopen.check(self, "accelerate_" .. i) then return i end
    end
    return lv
end

return _M
