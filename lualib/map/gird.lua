local core = require "gird.core"
local log = require "log"
--[[
{ "load", loadcfg },
{ "dump", debug_dump },
{ "dump_neibo", debug_neibo },
{ "isconnex", check_connex },
{ "isneibo", check_neibo },
{ "getneibo", get_neibo },
{ "query", lgirdinfo_query },
]]

local _M = {}
local CM
local LAYER, STOP = {}, {}

function _M.init(name)
    CM = core.query(name)
end

-- 目标层数不能为0
function _M.isconnex(from, to)
    local stop_to = STOP[to]
    if stop_to then return false end
    local ok, e = core.isconnex(CM, from, to, LAYER[from], LAYER[to])
    if not ok then
        log("isconnex from %d to %d,e %s", from, to, e)
        print(core.dump(CM, from))
    end
    return ok
end

function _M.isneibo(from, to)
    local ok, e = core.isneibo(CM, from, to, LAYER[from], LAYER[to])
    if not ok then
        print("isneibo", from, to, e)
        print(core.dump(CM, from))
    end
    return ok
end

function _M.getneibo(from, direct)
    local ok, dest, from_layer, dest_layer = core.getneibo(CM, from, direct)
    if not ok then
        log("getneibo err from %d,direct %d,e%s", from, direct, dest)
        return false
    end
    return ok, dest, from_layer, dest_layer
end

function _M.stop(pos)
    STOP[pos] = (STOP[pos] or 0) + 1
end

function _M.getstop(pos)
    return STOP[pos]
end

function _M.unstop(pos)
    local n = (STOP[pos] or 0) - 1
    assert(n >= 0)
    if n == 0 then n = nil end
    STOP[pos] = n
end

function _M.layer(pos, layer)
    assert(not LAYER[pos] and layer > 0)
    LAYER[pos] = layer
end

function _M.getlayer(pos)
    return LAYER[pos]
end

function _M.unlayer(pos)
    assert(LAYER[pos])
    LAYER[pos] = nil
end

function _M.check(to)
    if STOP[to] then return false end
    return core.layer(CM, to) > 0
end

return _M
