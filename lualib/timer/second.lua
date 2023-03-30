local skynet = require "skynet"
local timer = require "timer"
local utime = require "util.time"

local ceil = math.ceil
local coroutine = coroutine

local _M = {}

function _M.add(ti, cb)
    return timer.add(ti * 100, cb)
end

local function addexpire(expire, cb)
    local now = utime.time()
    local diff = expire - now
    return timer.add(ceil(diff * 100), cb)
end

_M.addexpire = addexpire

function _M.del(id)
    return timer.del(id)
end

function _M.wait(ti)
    local co = coroutine.running()
    _M.add(ti, function()
        skynet.wakeup(co)
    end)
    skynet.wait(co)
end

function _M.wait_to(expire)
    local co = coroutine.running()
    addexpire(expire, function()
        skynet.wakeup(co)
    end)
    skynet.wait(co)
end

return _M
