local skynet = require "skynet"
local objmgr = require "map.objmgr"
local cfgproxy = require "cfg.proxy"
local itemtype = require "map.itemtype"
local cache = require("map.cache")("bag")
local supply = require "map.supply"
local schema = require "mongo.schema"
local mode = require "map.fight_mode"
local _LUA = require "handler.lua"

local CFG
skynet.init(function()
    CFG = cfgproxy("item_temp")
end)

cache.schema(schema.SAR())

local OPEN

local _M = {}

require("map.mods") {
    name = "bag",
    init = function(ctx)
        if ctx.fight_mode == mode.supply then OPEN = true end
    end,
    enter = function()
        if not OPEN then return end
        objmgr.clientpush("map_bag", {list = cache.get()})
    end
}

local function add_one(id, cnt)
    assert(OPEN and CFG[id] and cnt > 0)
    local C = cache.get()
    C[id] = (C[id] or 0) + cnt
    cache.dirty()
    objmgr.clientpush("map_bag_change", {id = id, change = cnt})
    return C[id]
end

local function del_one(id, cnt)
    assert(OPEN and CFG[id] and cnt > 0)
    local C = cache.get()
    local old_cnt = C[id] or 0
    if old_cnt < cnt then return false end
    if old_cnt == cnt then
        C[id] = nil
    else
        C[id] = old_cnt - cnt
    end
    cache.dirty()
    objmgr.clientpush("map_bag_change", {id = id, change = -cnt})
    return C[id] or 0
end

local function check_del(rewards)
    local C = cache.get()
    for _, v in ipairs(rewards) do
        local id, cnt = v[1], v[2]
        assert(OPEN and CFG[id] and cnt > 0)
        if (C[id] or 0) < cnt then return false end
    end
    return true
end

_M.check_del = check_del

function _M.add(rewards)
    check_del(rewards)
    for _, v in ipairs(rewards) do add_one(v[1], v[2]) end
    return true
end

function _M.del(rewards)
    if not check_del(rewards) then return false end
    for _, v in ipairs(rewards) do del_one(v[1], v[2]) end
    return true
end

local itemuse = {
    [itemtype.medicine] = function(id, cnt, usepara)
        local C = cache.get()
        if (C[id] or 0) < cnt then return false, 22 end
        local val, max = supply.get()
        if val >= max then return false, 23 end
        if cnt - 1 > 0 and val + (cnt - 1) * usepara >= max then
            return false, 24
        end
        if _M.del({{id, cnt}}) then
            supply.add(cnt * usepara)
            return true
        else
            return false, 25
        end
    end
}
function _LUA.map_itemuse(rid, id, cnt)
    if not OPEN then return false, 24 end
    local ply = objmgr.player()
    assert(rid == ply.uuid)
    local cfg = CFG[id]
    if not cfg then return false, 20 end
    local fn = itemuse[cfg.type]
    if not fn then return false, 21 end

    local ok, err = fn(id, cnt, cfg.usepara)
    if not ok then return false, err end
    return true
end

return _M
