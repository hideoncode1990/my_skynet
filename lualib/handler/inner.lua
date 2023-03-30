local skynet = require "skynet"
local service = require "service"
local _LUA = require "handler.lua"

local _M = {}

local function dispatch(_, _, cmd, ...)
    local f = _M[cmd]
    if f then
        service.ret(f(...))
    else
        skynet.response()(false)
        error(string.format("Unknown command : [%s]", cmd))
    end
end

skynet.register_protocol {
    name = "inner",
    id = 101,
    pack = skynet.pack,
    unpack = skynet.unpack,
    dispatch = dispatch
}

function _LUA.inner(cmd, ...)
    return _M[cmd](...)
end

return _M
