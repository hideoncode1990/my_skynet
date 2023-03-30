local client = require "client"
local CACHE = {}

local _M = {}

function _M.newfd()
    CACHE = {}
end

function _M.enter(self, nm, t, data)
    CACHE[nm] = true
    client.push(self, t, data)
end

function _M.push(self, nm, t, data)
    if not CACHE[nm] then return end

    client.push(self, t, data)
    return true
end

return _M

