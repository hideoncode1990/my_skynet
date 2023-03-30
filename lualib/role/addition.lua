local event = require "role.event"
local _M = {}

local REGS = {}
function _M.reg(name, call)
    REGS[name] = call
end

local cache_any = {}
local function any(self, k)
    local r
    local function check()
        r = true
    end
    for _, c in pairs(REGS) do
        c(self, k, check)
        if r then return true end
    end
    return false
end

local cache_sum = {}
local function sum(self, k)
    local r = 0
    local function check(v)
        r = r + tonumber(v)
    end
    for _, c in pairs(REGS) do c(self, k, check) end
    return r
end

function _M.any(self, k)
    local r = cache_any[k]
    if r == nil then
        r = any(self, k)
        cache_any[k] = r
    end
    return r
end

function _M.sum(self, k)
    local r = cache_sum[k]
    if r == nil then
        r = sum(self, k)
        cache_sum[k] = r
    end
    return r
end

function _M.dirty(self)
    cache_any, cache_sum = {}, {}
    event.occur("EV_ADDITION_CHANGE", self)
end

return _M
