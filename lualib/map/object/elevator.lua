local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local objmgr = require "map.objmgr"
local objtype = require "map.objtype"
local gird = require "map.gird"
local selftype = require("map.objtype").elevator
local trigger = require "map.trigger"

local _LUA = require "handler.lua"

local _M = objmgr.class(selftype)

local CFG
skynet.init(function()
    CFG = cfgproxy("object_elevator")
end)

local MANUAL<const> = 1 -- 点自己就触发
local BYSWITCH<const> = 2 -- 点开关触发

function _M.new(uuid, id, pos)
    return {id = id, pos = pos, uuid = uuid, state = 0}
end

function _M.renew(o)
    if o.state == 1 then gird.layer(o.pos, CFG[o.id].layer) end
    return o
end

function _M.pack(self)
    return "map_elevator", self
end

function _M.onadd(self)

end

function _M.ondel(self)

end

local function execute(self, cfg)
    self.state = self.state ~ 1
    self.times = (self.times or 0) + 1
    objmgr.dirty()

    if self.state == 1 then
        gird.layer(self.pos, cfg.layer)
    else
        gird.unlayer(self.pos)
    end
    objmgr.clientpush("map_elevator_state", self)
    trigger.invoke("elevator_change")
end

function _M.execute(self)
    local cfg = CFG[self.id]
    assert(cfg.type == BYSWITCH)
    execute(self, cfg)
end

function _LUA.map_elevator(rid, uuid)
    local ply = objmgr.player()
    assert(rid == ply.uuid)
    local o = objmgr.grab(uuid, objtype.elevator)
    local cfg = CFG[o.id]
    assert(cfg.type == MANUAL)
    if ply.pos ~= o.pos then return false, 10 end

    execute(o, cfg)
    return true
end

return _M
