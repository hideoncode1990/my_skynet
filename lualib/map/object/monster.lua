local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local objmgr = require "map.objmgr"
local env = require "map.env"
local trigger = require "map.trigger"
local monster_die = require "map.monster_die"
local target = require "map.target"

local selftype = require("map.objtype").monster
local _M = objmgr.class(selftype)

local CFG
skynet.init(function()
    CFG = cfgproxy("object_monster")
end)

local function new(id)
    local cfg = CFG[id]
    for _, v in ipairs(cfg) do
        if env.mainline >= v.mainline then
            return assert(v.monster), v.label
        end
    end
    assert(false)
end

function _M.new(uuid, id, pos)
    local monster, label = new(id)
    return {id = id, pos = pos, uuid = uuid, monster = monster, label = label}
end

function _M.renew(o)
    return o
end

-- simple information of heroes for monster_die
function _M.die(self, simple)
    monster_die.add(self.uuid, simple)
    target.finish(target.type.monster_die, self.label)
    trigger.invoke("monster")
end

_M.change_check = new

function _M.change_id(self, monster, label)
    self.monster = monster
    self.label = label
    objmgr.dirty()
    objmgr.clientpush(_M.pack(self))
end

function _M.pack(self)
    return "map_monster", self
end

return _M
