local skynet = require "skynet"
local mcast = require "mcast"
local variabled
local _MT = {
    __index = function(t, k)
        local v = skynet.call(variabled, "lua", "query", k)
        t[k] = v
        return v
    end,
    __call = function(t, k, v)
        skynet.call(variabled, "lua", "change", k, v)
        t[k] = v
    end
}

local _M = setmetatable({}, _MT)

skynet.init(function()
    variabled = skynet.uniqueservice("base/variabled")
    mcast("variable.change", function()
        local cache = {}
        for k in pairs(_M) do
            local v = _MT.__index(cache, k)
            _M[k] = v
            skynet.error("variable update", k, v)
        end
    end):subscribe()
end)

return _M
