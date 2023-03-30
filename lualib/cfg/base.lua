local sharetable = require "skynet.sharetable"
local skynet = require "skynet"
local queue = require "skynet.queue"
local mcast = require "mcast"
local parallels = require "parallels"

local _M = {}

local auto_Q = setmetatable({}, {
    __index = function(t, k)
        local Q = queue()
        t[k] = Q
        return Q
    end
})

local function just_query(t, k)
    local v = assert(sharetable.query(k), "not found " .. k)
    t[k] = v
    return v
end

local function query(t, k)
    local v = rawget(t, k)
    if v then return v end
    return just_query(t, k)
end

local CACHES = setmetatable({}, {
    __index = function(t, k)
        local _t = auto_Q[k](query, t, k)
        auto_Q[k] = nil
        return _t
    end
})

_M.CACHES = CACHES

local CBS, CBS_ALL, STOP = {}, {}, {}
skynet.init(function()
    mcast("cfgupdate", function(changes)
        local t = CACHES
        local pa = parallels()
        local chgs = {}
        if STOP == true then return end
        for k in pairs(changes) do
            if rawget(t, k) and not STOP[k] then
                local cbs = CBS[k]
                if cbs then chgs[k] = cbs end
                pa:add(function()
                    skynet.error("requery cfg", k)
                    auto_Q[k](just_query, t, k)
                    auto_Q[k] = nil
                end)
            end
        end
        pa:wait()
        local pa2 = parallels()
        for _, cb in pairs(CBS_ALL) do pa2:add(cb, changes) end
        pa2:wait()
        for _, cbs in pairs(chgs) do
            for _, cb in pairs(cbs) do skynet.fork(cb) end
        end
    end):subscribe()
end)

function _M.onchange(cb, nm)
    local cbs = CBS[nm]
    if not cbs then
        cbs = {cb}
        CBS[nm] = cbs
    else
        table.insert(cbs, cb)
    end
end

function _M.onchangeall(cb, nm)
    CBS_ALL[nm] = cb
end

function _M.stopchange(...)
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        STOP[key] = true
    end
end

function _M.stopall()
    STOP = true
end

return _M
