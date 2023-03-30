local skynet = require "skynet"
local unique = require "service.unique"

local _M = {}

function _M.call_loaded(...)
    return skynet.call(unique["game/manager"], "lua", "agent_call_loaded", ...)
end

function _M.send_loaded(...)
    return skynet.send(unique["game/manager"], "lua", "agent_send_loaded", ...)
end

function _M.call(...)
    return skynet.call(unique["game/manager"], "lua", "agent_call", ...)
end

function _M.send(...)
    return skynet.send(unique["game/manager"], "lua", "agent_send", ...)
end

function _M.send_online_all(...)
    return skynet.send(unique["game/manager"], "lua", "agent_send_online_all",
        ...)
end

return _M
