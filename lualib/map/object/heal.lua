local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local objmgr = require "map.objmgr"
local objtype = require "map.objtype"
local map_attrs = require "map.attrs"
local gird = require "map.gird"
local map_hero = require "map.hero"

local selftype = require("map.objtype").heal

local _LUA = require "handler.lua"
local _M = objmgr.class(selftype)

local CFG
skynet.init(function()
    CFG = cfgproxy("object_heal")
end)

function _M.new(uuid, id, pos)
    return {id = id, pos = pos, uuid = uuid}
end

function _M.renew(o)
    return o
end

function _M.del(self)

end

function _M.pack(self)
    return "map_heal", self
end

local function execute(tp, para)
    if tp == 1 then
        map_attrs.heal_revival_random(para)
    elseif tp == 2 then
        map_attrs.heal_cure_live_only(para)
    elseif tp == 3 then
        map_attrs.heal_all_full(map_hero.get_all(0))
    else
        assert(false)
    end
end

function _LUA.map_heal(rid, uuid)
    local ply = objmgr.player()
    assert(rid == ply.uuid)
    local o = objmgr.grab(uuid, objtype.heal)
    if not o then return false, 2 end

    if not gird.isneibo(ply.pos, o.pos) then return false, 5 end

    local cfg = CFG[o.id]
    ply.lock(execute, cfg.type, cfg.para)
    objmgr.del(uuid)
    return true
end

return _M
