local skynet = require "skynet"
local sharetable = require "skynet.sharetable"
local mcast = require "mcast"

local CBS = {}

local same_table
local function same_value(lv, rv)
    if lv ~= rv then
        local type_lv, type_rv = type(lv), type(rv)
        if type_lv == "table" and type_lv == type_rv then
            return same_table(lv, rv)
        else
            return false
        end
    else
        return true
    end
end

function same_table(l, r)
    local ks = {}
    for k, lv in pairs(l) do
        local rv = r[k]
        if not same_value(lv, rv) then return false end
        ks[k] = true
    end
    for k, rv in pairs(r) do
        if not ks[k] then
            local lv = l[k]
            if not same_value(lv, rv) then return false end
        end
    end
    return true
end

local function compare_and_load(name, tbl)
    local data_name = "setting." .. name
    local old = sharetable.query(data_name)
    if not same_value(tbl, old) then
        sharetable.loadtable(data_name, tbl)
        mcast("setting"):publish(name)
    end
end

local _M = {}

function _M.load(name, tbl)
    compare_and_load(name, tbl)
end

local LOCK = require("skynet.queue")()
local function query(t, k)
    local v = rawget(t, k)
    if v then return v end
    v = sharetable.query("setting." .. k)
    t[k] = v
    return v
end

local CACHE = setmetatable({}, {
    __index = function(t, k)
        return LOCK(query, t, k)
    end
})

mcast("setting", function(name)
    if rawget(CACHE, name) then
        local cbs = CBS[name]
        CACHE[name] = sharetable.query("setting." .. name)
        for _, cb in ipairs(cbs) do skynet.fork(cb) end
    end
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

_M.CACHE = CACHE

function _M.proxy(name)
    local p = setmetatable({}, {
        __index = function(_, k)
            return CACHE[name][k]
        end,
        __pairs = function()
            local t = CACHE[name]
            return pairs(t)
        end,
        __call = function(_, cb)
            _M.onchange(cb, name)
        end,
        __len = function()
            local t = CACHE[name]
            return #t
        end
    })
    local _, main = coroutine.running()
    if main then
        skynet.init(function()
            local _ = CACHE[name]
        end)
    else
        local _ = CACHE[name]
    end
    return p
end

return _M
