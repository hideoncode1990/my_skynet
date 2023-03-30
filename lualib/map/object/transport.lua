local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local objmgr = require "map.objmgr"
local objtype = require "map.objtype"
local trigger = require "map.trigger"
local gird = require "map.gird"

local selftype = require("map.objtype").transport

local _LUA = require "handler.lua"
local _M = objmgr.class(selftype)

local CFG
skynet.init(function()
    CFG = cfgproxy("object_transport")
end)

local tp_inner = {
    auto = 1, -- 自动传，不是阻挡，需要走到传送点上面
    manual = 2 -- 手动点击传送，是阻挡。需要挨着传送点
}

function _M.new(uuid, id, pos)
    return {id = id, pos = pos, uuid = uuid}
end

function _M.renew(o)
    return o
end

function _M.pack(self)
    return "map_transport", self
end

function _M.onadd(self)
    local tp = CFG[self.id].para[1]
    if tp == tp_inner.manual then gird.stop(self.pos) end
end

function _M.ondel(self)
    local tp = CFG[self.id].para[1]
    if tp == tp_inner.manual then gird.unstop(self.pos) end
end

local function get_para(self)
    local para = CFG[self.id].para
    return para[1], para[2]
end

function _M.arrival(self)
    local tp, desti = get_para(self)
    assert(tp == tp_inner.auto)
    local ply = objmgr.player()
    ply.transfer_to(desti)
    trigger.invoke("transport", self.uuid)
end

function _LUA.map_transport(rid, uuid)
    local ply = objmgr.player()
    assert(rid == ply.uuid)
    local o = objmgr.grab(uuid, objtype.transport)
    if not gird.isneibo(ply.pos, o.pos) then return false, 5 end
    local tp, desti = get_para(o)
    if not tp == tp_inner.manual then return false, 8 end
    ply.transfer_to(desti)
    trigger.invoke("transport", uuid)
    return true
end
