local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local objmgr = require "map.objmgr"
local supply = require "map.supply"
local map_hero = require "map.hero"
local map_attrs = require "map.attrs"

local selftype = require("map.objtype").trap

local _M = objmgr.class(selftype)

local CFG
skynet.init(function()
    CFG = cfgproxy("object_trap")
end)

function _M.new(uuid, id, pos)
    return {id = id, pos = pos, uuid = uuid}
end

function _M.renew(o)
    return o
end

function _M.pack(self)
    return "map_trap", self
end

function _M.onadd()
end
function _M.ondel()
end
-- 1 扣血 2 加血
local function arrival(self)
    if not supply.check() then return end
    local cfg = CFG[self.id]
    local para = cfg.para
    local tp, feature, val = para[1], para[2], para[3] * 100
    if tp == 1 then
        local all_heroes = map_hero.get_all(feature)
        map_attrs.trap_hp_del(val, feature, all_heroes)
    elseif tp == 2 then
        map_attrs.trap_hp_add(val, feature)
    end
    if not cfg.exist then objmgr.del(self.uuid) end
end

function _M.arrival(self)
    local ply = objmgr.player()
    return ply.lock(arrival, self)
end

return _M
