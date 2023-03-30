local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local objmgr = require "map.objmgr"
local env = require "map.env"
local objtype = require "map.objtype"
local utable = require "util.table"
local _LUA = require "handler.lua"
local map_hero = require "map.hero"
local gird = require "map.gird"
local source = require "map.source"
local selftype = require("map.objtype").herotower
local _M = objmgr.class(selftype)

local CNT = 4

local CFG_STAGE, CFG_RAN
skynet.init(function()
    CFG_STAGE, CFG_RAN = cfgproxy("herotower_stage", "herotower_random")
end)

local function random_group()
    local cfg = CFG_STAGE[env.average_st] or CFG_STAGE[#CFG_STAGE]
    local group = cfg.group
    cfg = CFG_RAN[group]
    local list, size = utable.copy(cfg.list), cfg.size
    local ret = {}
    for _ = 1, CNT do
        local ran, pro = math.random(1, size), 0
        for k, v in ipairs(list) do
            local hero, weight = v[1], v[2]
            pro = pro + weight
            if ran <= pro then
                table.remove(list, k)
                size = size - weight
                table.insert(ret, {hero = hero, group = group})
                break
            end
        end
    end
    return ret
end

function _M.new(uuid, id, pos)
    return {id = id, pos = pos, uuid = uuid, info = random_group()}
end

function _M.renew(o)
    return o
end

function _M.pack(self)
    return "map_herotower", self
end

local function create_add(target)
    map_hero.add({id = target.hero, group = target.group}, source.herotower)
end

function _LUA.map_herotower(rid, uuid, index)
    local ply = objmgr.player()
    assert(rid == ply.uuid)
    local o = objmgr.grab(uuid, objtype.herotower)
    if not o then return false, 2 end

    if not gird.isneibo(ply.pos, o.pos) then return false, 5 end
    local target = o.info[index]
    if not target then return false, 8 end

    create_add(target)
    objmgr.del(uuid)
    return true
end

return _M
