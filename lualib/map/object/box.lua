local skynet = require "skynet"
local objmgr = require "map.objmgr"
local cfgproxy = require "cfg.proxy"
local trigger = require "map.trigger"
local objtype = require "map.objtype"
local env = require "map.env"
local supply = require "map.supply"
local monster_die = require "map.monster_die"
local drop = require "role.drop"
local uaward = require "util.award"
local gird = require "map.gird"
local box_opened = require "map.box_opened"
local _LUA = require "handler.lua"
local target = require "map.target"
local selftype = require("map.objtype").box

local _M = objmgr.class(selftype)

local CFG_C, CFG
skynet.init(function()
    CFG_C, CFG = cfgproxy("object_boxcreate", "object_box")
end)

function _M.new(uuid, id, pos)
    local cfg = CFG_C[id]
    local box, label, k
    for _, v in ipairs(cfg) do
        if env.mainline >= v.mainline then
            box = v.box
            label = v.label
            k = v.k
            break
        end
    end
    assert(box)
    if box_opened.check(uuid) then return end
    return {id = id, pos = pos, uuid = uuid, box = box, label = label, k = k}
end

function _M.renew(o)
    return o
end

function _M.init(self)
    return self
end

local check_call = {
    [1] = function(id)
        return trigger.checkfinish(id)
    end,
    [2] = function(uuid)
        return monster_die.check(uuid)
    end
}

function _M.getcfg(self)
    return CFG[self.k]
end

function _M.open_check(self)
    local cfg = _M.getcfg(self)
    if cfg.condition then
        for _, args in pairs(cfg.condition) do
            local ret = true
            for _, v in ipairs(args) do
                if not check_call[v[1]](v[2]) then
                    ret = false
                    break
                end
            end
            if ret then return true end
        end
        return false
    end
    return true
end

function _M.pack(self)
    return "map_box", self
end

local function get_drop(id)
    return id and drop.calc(id, 1) or {}
end

function _LUA.map_box(rid, uuid)
    if not supply.check() then return false, 107 end
    if box_opened.check(uuid) then return false, 8 end

    local ply = objmgr.player()
    assert(rid == ply.uuid)
    local o = objmgr.grab(uuid, objtype.box)
    if not o then return false, 8 end

    if not gird.isneibo(ply.pos, o.pos) then return false, 5 end
    if not o:open_check() then return false, 7 end

    local cfg = o:getcfg()
    objmgr.del(uuid)
    box_opened.add(o)
    target.finish(target.type.box_open, o.label)
    trigger.invoke("box_get")
    local ctx = uaward().append(get_drop(cfg.drop), cfg.reward or {})
    return ctx.result
end

return _M
