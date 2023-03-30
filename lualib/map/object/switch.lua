local skynet = require "skynet"
local objmgr = require "map.objmgr"
local cfgproxy = require "cfg.proxy"
local objtype = require "map.objtype"
local supply = require "map.supply"
local gird = require "map.gird"
local trigger = require "map.trigger"

local selftype = require("map.objtype").switch

local _LUA = require "handler.lua"
local _M = objmgr.class(selftype)

local CFG

skynet.init(function()
    CFG = cfgproxy("object_switch")
end)

function _M.new(uuid, id, pos)
    local cfg = CFG[id]
    local sw_init = cfg.init or 1
    assert(cfg.max >= sw_init)
    return {id = id, pos = pos, uuid = uuid, sw = sw_init}
end

function _M.renew(o)
    return o
end

function _M.switch(self)
    _M.send(self, self.target, "switch")
end

function _M.connect(self, target)
    self.target = target
end

function _M.pack(self)
    return "map_switch", self
end

function _M.execute(self)
    local cfg = CFG[self.id]
    local sw = self.sw
    sw = sw + 1
    if sw > cfg.max then sw = 1 end
    self.sw = sw
    self.times = (self.times or 0) + 1
    objmgr.dirty()

    objmgr.clientpush("map_switch_state", self)
    for _, uuid in ipairs(cfg.obj or {}) do
        local o = objmgr.grab(uuid)
        o:execute()
    end
    trigger.invoke("switch_change")
end

function _LUA.map_switch(rid, uuid)
    if not supply.check() then return false, 107 end
    local ply = objmgr.player()
    assert(rid == ply.uuid)
    local o = objmgr.grab(uuid, objtype.switch)
    if not gird.isneibo(ply.pos, o.pos) then return false, 5 end
    o:execute()
end

return _M
