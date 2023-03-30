local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local log = require "log"
local utable = require "util.table"
local rwlock = require "rwqueue"()
local TYPES, SAMETYPE, MAINTYPE
skynet.init(function()
    TYPES, SAMETYPE, MAINTYPE = cfgproxy("task_type", "task_sametype",
        "task_maintype")
end)
local _M = {}

require("role.mods") {
    name = "task_trigger",
    unload = function()
        rwlock(true, function()
        end)
    end
}

local CBS = {}
function _M.reg(name, cb)
    CBS[name] = cb
end

function _M.unreg(name)
    CBS[name] = nil
end

local function trigger(self, tp, val)
    for _, cb in pairs(CBS) do
        local ok, err = xpcall(cb, debug.traceback, self, tp, val)
        if not ok then log(err) end
    end
end

function _M.trigger(...)
    rwlock(false, trigger, ...)
end

local function unique_cache(maintype, cfg, data)
    local metatable = getmetatable(data)
    if not metatable then
        local cache = {}
        for _, d in ipairs(data) do
            local v = d[2]
            for _, l in ipairs(cfg) do
                local k = maintype .. l
                if v >= l then
                    cache[k] = (cache[k] or 0) + 1
                else
                    break
                end
            end
        end
        metatable = {__index = cache}
        setmetatable(data, metatable)
    end
    return metatable.__index
end

function _M.cache(_, data, NM)
    local ret = {}
    for k, v in pairs(data or {}) do
        if type(v) == "table" then
            local cfg = SAMETYPE[NM][k]
            local cache = unique_cache(k, cfg, v)
            for m, n in pairs(cache) do ret[m] = n end
        else
            ret[k] = v
        end
    end
    return ret
end

local MAX = 30

local calc_handler = {
    add = function(tp, val, C, done)
        local v = (C[tp] or 0) + (val or 1)
        C[tp], done[tp] = v, v
        return true
    end,
    more = function(tp, val, C, done)
        local ov = C[tp] or 0
        local v = math.max(ov, (val or 1))
        if v ~= ov then
            C[tp], done[tp] = v, v
            return true
        end
    end,
    set = function(tp, val, C, done)
        local ov = C[tp]
        val = val or 1
        if ov ~= val then
            C[tp], done[tp] = val, val
            return true
        end
    end,
    unique = function(tp, val, C, done, NM)
        local maintype = tp.maintype
        local arg = assert(tp.arg)
        local cfg = SAMETYPE[NM][maintype]
        if not cfg then return end
        if arg < cfg[1] then return end
        local find
        local data = utable.sub(C, maintype)
        local cache = unique_cache(maintype, cfg, data)

        local begin, over = 0, arg
        for _, d in ipairs(data) do
            if d[1] == val then
                begin = d[2]
                if arg <= begin then return end
                d[2] = arg
                find = true
                break
            end
        end

        if not find then table.insert(data, {val, arg}) end
        table.sort(data, function(left, right)
            return left[2] > right[2]
        end)

        if not find and #data > MAX then begin = table.remove(data)[2] end

        for _, l in ipairs(cfg) do
            if l > begin then
                if l <= over then
                    local k = maintype .. l
                    cache[k] = (cache[k] or 0) + 1
                    done[k] = data[k]
                else
                    break
                end
            end
        end
    end
}

function _M.type(tp)
    if type(tp) == "table" then
        return tp.maintype .. tp.arg, false
    else
        return tp, true
    end
end

local function calc(mark, tp, C, val, done, NM)
    local f = calc_handler[mark]
    local ok, err = pcall(f, tp, val, C, done, NM)
    if not ok then log(err) end
end

function _M.calc(tp, C, val, NM)
    local done = {}
    if type(tp) == "table" then
        calc(TYPES[tp.maintype], tp, C, val, done, NM)
    else
        calc(TYPES[tp], tp, C, val, done, NM)
    end
    return done
end

local check_handler = {
    add = function(arg, C, tp)
        local v = C[tp] or 0
        return v >= arg
    end,
    more = function(arg, C, tp)
        local v = C[tp] or 0
        return v >= arg
    end,
    set = function(arg, C, tp)
        local v = C[tp] or 0
        return v >= arg
    end,
    unique = function(arg, C, tp, NM)
        local maintype = MAINTYPE[tp]
        local cfg = SAMETYPE[NM][maintype]
        if not cfg then return end

        local data = utable.getsub(C, maintype)
        unique_cache(maintype, cfg, data)
        local v = data[tp] or 0
        return v >= arg
    end
}
function _M.check(tp, arg, C, NM)
    local mark = TYPES[tp]
    local f = check_handler[mark]
    return f(arg, C, tp, NM)
end

return _M

