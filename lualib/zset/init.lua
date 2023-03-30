local skynet = require "skynet"

local zsetmgr
skynet.init(function()
    zsetmgr = skynet.uniqueservice("base/zsetmgr")
end)

local address = setmetatable({}, {
    __index = function(t, id)
        local addr = skynet.call(zsetmgr, "lua", "reg", id)
        rawset(t, id, addr)
        return addr
    end
})

local _M = {}

---@class zset_param
---@field id integer
---@field value integer
---@field timestap integer

---@param args zset_param
function _M.add(nm, args)
    skynet.call(address[nm], "lua", "add", args)
end

---@param args zset_param
function _M.set(nm, args)
    skynet.call(address[nm], "lua", "set", args)
end

function _M.del(nm, id)
    skynet.call(address[nm], "lua", "del", id)
end

function _M.limit(nm, count)
    skynet.call(address[nm], "lua", "limit", count)
end

function _M.count(nm)
    return skynet.call(address[nm], "lua", "count")
end

---@return integer
function _M.rank(nm, id)
    return skynet.call(address[nm], "lua", "rank", id)
end

function _M.add_return(nm, id)
    return skynet.call(address[nm], "lua", "rank_return", id)
end

---@return integer
---@return zset_param
function _M.rank_obj(nm, id)
    return skynet.call(address[nm], "lua", "rank_obj", id)
end

---@return integer[]
function _M.range(nm, r1, r2)
    return skynet.call(address[nm], "lua", "range", r1, r2)
end

---@return zset_param[]
function _M.range_objs(nm, r1, r2)
    return skynet.call(address[nm], "lua", "range_objs", r1, r2)
end

---@return integer[]
function _M.range_byvalue(nm, r1, r2)
    return skynet.call(address[nm], "lua", "range_byvalue", r1, r2)
end

---@return zset_param[]
function _M.range_byvalue_objs(nm, r1, r2)
    return skynet.call(address[nm], "lua", "range_byvalue_objs", r1, r2)
end

return _M
