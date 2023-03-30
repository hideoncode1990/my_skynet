local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local objmgr = require "map.objmgr"
local trigger = require "map.trigger"
local gird = require "map.gird"
local deltype = require "map.deltype"
local selftype = require("map.objtype").door
local _M = objmgr.class(selftype)

local CFG
skynet.init(function()
    CFG = cfgproxy("object_door")
end)

function _M.new(uuid, id, pos)
    return {id = id, pos = pos, uuid = uuid, sw = CFG[id].state}
end

function _M.renew(o)
    return o
end

function _M.pack(self)
    return "map_door", self
end

local function get_change_list(self)
    local cfg_stop = CFG[self.id].stop
    local self_pos = self.pos
    if cfg_stop then
        local list = {}
        for _, v in ipairs(cfg_stop) do
            table.insert(list, v)
            if v == self_pos then return cfg_stop end
        end
        table.insert(list, self_pos)
        return list
    else
        return {self_pos}
    end
end

local function multi_add_stop(self)
    for _, pos in ipairs(get_change_list(self)) do gird.stop(pos) end
end

local function multi_clean_stop(self)
    for _, pos in ipairs(get_change_list(self)) do gird.unstop(pos) end
end

function _M.onadd(self)
    if self.sw == 0 then multi_add_stop(self) end
end

function _M.ondel(self)
    if self.sw == 0 then multi_clean_stop(self) end
end

function _M.execute(self, final_state)
    if final_state and self.sw == final_state then return end
    self.sw = self.sw ~ 1
    self.times = (self.times or 0) + 1
    objmgr.dirty()
    if self.sw == 1 then
        multi_clean_stop(self)
    else
        multi_add_stop(self)
    end
    objmgr.clientpush("map_door_state", self)
    trigger.invoke("door_change")
end

function _M.be_shot(self)
    if CFG[self.id].be_shot then
        objmgr.del(self.uuid, deltype.be_shot)
        return true
    end
end

return _M
