local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local objmgr = require "map.objmgr"
local trigger = require "map.trigger"
local utable = require "util.table"
local env = require "map.env"
local udrop = require "util.drop"
local _LUA = require "handler.lua"
local objtype = require "map.objtype"
local gird = require "map.gird"
local selftype = require("map.objtype").shop
local _M = objmgr.class(selftype)

local CFG, CFG_ITEM, CFG_PDF
skynet.init(function()
    CFG, CFG_ITEM, CFG_PDF = cfgproxy("object_shop", "object_shop_item",
        "object_pdf")
end)

local item_cnt = 4

function _M.new(uuid, id, pos)
    local pool
    for _, v in ipairs(CFG) do
        if env.mainline >= v.mainline then
            pool = v.pool
            break
        end
    end
    assert(pool)
    local items = {}
    for _, v in ipairs(udrop.multi(CFG_PDF[pool], item_cnt)) do
        table.insert(items, {id = v})
    end
    return {id = id, pos = pos, uuid = uuid, items = items}
end

function _M.renew(o)
    return o
end

function _M.pack(self)
    return "map_shop", self
end

function _LUA.map_shop_buy(rid, uuid, index)
    local ply = objmgr.player()
    assert(rid == ply.uuid)
    local o = objmgr.grab(uuid, objtype.shop)
    if not gird.isneibo(ply.pos, o.pos) then return false, 5 end
    local info = o.items[index]
    local id, bought = info.id, info.bought
    local cfg = CFG_ITEM[id]
    if not cfg then return false, 13 end
    if bought then return false, 14 end
    local ok, err = objmgr.agent_call("award_deladd", {
        flag = "map_shop_buy",
        arg1 = uuid,
        arg2 = id
    }, {cfg.cost}, {cfg.item})

    if not ok then
        return false, err
    else
        info.bought = true
        objmgr.dirty()
    end
    return true
end

function _LUA.map_shop_close(rid, uuid)
    local ply = objmgr.player()
    assert(rid == ply.uuid)
    local o = objmgr.grab(uuid, objtype.shop)
    if not o then return false, 2 end

    if not gird.isneibo(ply.pos, o.pos) then return false, 5 end
    objmgr.del(uuid)
    return true
end

return _M
