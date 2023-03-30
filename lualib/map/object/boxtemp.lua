local skynet = require "skynet"
local objmgr = require "map.objmgr"
local cfgproxy = require "cfg.proxy"
local objtype = require "map.objtype"
local _LUA = require "handler.lua"
local selftype = require("map.objtype").boxtemp
local bag = require "map.bag"
local gird = require "map.gird"

local _M = objmgr.class(selftype)

local CFG
skynet.init(function()
    CFG = cfgproxy("object_boxtemp")
end)

function _M.new(uuid, id, pos)
    assert(CFG[id])
    return {id = id, pos = pos, uuid = uuid}
end

function _M.renew(o)
    return o
end

function _M.init(self)
    return self
end

function _M.pack(self)
    return "map_boxtemp", self
end

function _LUA.map_boxtemp(rid, uuid)
    local ply = objmgr.player()
    assert(rid == ply.uuid)
    local o = objmgr.grab(uuid, objtype.boxtemp)
    if not o then return false, 2 end

    if not gird.isneibo(ply.pos, o.pos) then return false, 5 end
    objmgr.del(uuid)
    assert(bag.add(CFG[o.id].reward))
    return true
end

return _M
