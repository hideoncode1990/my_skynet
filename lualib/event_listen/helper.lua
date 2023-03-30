local skynet = require "skynet"
local uniq = require "uniq.c"
local _R = require "handler.inner"

local _M = {}
local CBLIST = {}

local MT = {
    __close = function(t)
        local addr = t.addr
        if addr then
            t.addr = nil
            CBLIST[t.uniq_id] = nil
            skynet.send(addr, "inner", "event_unsubscribe", t.uniq_id, t.ev)
        end
    end
}

function _M.subscribe(addr, ev, cb, ...)
    local uniq_id = uniq.id()
    skynet.call(addr, "inner", "event_subscribe", skynet.self(), uniq_id, ev,
        ...)
    local ret = setmetatable({addr = addr, uniq_id = uniq_id, cb = cb, ev = ev},
        MT)
    CBLIST[uniq_id] = ret
    return ret
end

function _M.unsubscribe(ret)
    MT.__close(ret)
end

function _M.wait(addr, event, ...)
    return pcall(skynet.call, addr, "inner", "event_wait", event, ...)
end

function _R.subscribe_return(uniq_id, ...)
    local ret = CBLIST[uniq_id]
    if ret then return ret.cb(...) end
end

return _M
