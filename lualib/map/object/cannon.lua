local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local objtype = require "map.objtype"
local objmgr = require "map.objmgr"
local trigger = require "map.trigger"
local gird = require "map.gird"
local selftype = require("map.objtype").cannon
local _M = objmgr.class(selftype)

local _LUA = require "handler.lua"

local CFG
skynet.init(function()
    CFG = cfgproxy("object_cannon")
end)

function _M.new(uuid, id, pos)
    local cfg = CFG[id]
    return {
        id = id,
        pos = pos,
        uuid = uuid,
        fire = cfg.fire,
        direct = assert(cfg.direct)
    }
end

function _M.renew(o)
    return o
end

function _M.pack(self)
    return "map_cannon", self
end

function _M.be_shot(self)
    if self.fire then return end

    self.fire = 1
    objmgr.dirty()
    objmgr.clientpush("map_cannon_be_shot", self)
    return true
end

local function get_next(from, direct)
    local ok, dest, from_layer, dest_layer = gird.getneibo(from, direct)
    -- 数据错误
    if not ok then
        error(string.format("get_next wrong from:%d direct:%d", from, direct))
    end
    -- 边界
    if not dest then return false end

    from_layer = gird.getlayer(from) or from_layer
    dest_layer = gird.getlayer(dest) or dest_layer

    -- 配置中设置成的阻挡
    -- 高于from 的地层
    -- 逻辑层设置成的阻挡
    if dest_layer <= 0 or from_layer < dest_layer or gird.getstop(dest) then
        return false, dest
    end
    return true, dest -- 可以继续往该方向飞
end

function _LUA.map_cannon(rid, uuid)
    local ply = objmgr.player()
    assert(rid == ply.uuid)
    local o = objmgr.grab(uuid, objtype.cannon)
    if not o.fire then return false, 2 end
    if not gird.isneibo(ply.pos, o.pos) then return false, 5 end

    local from, over = o.pos, nil
    local direct = o.direct
    while true do
        local ok, dest = get_next(from, direct)
        if ok then
            from = dest
        else
            if dest then
                over = dest
                objmgr.be_shot(dest)
            else
                over = from
            end
            break
        end
    end
    objmgr.clientpush("map_cannon_fire", {begin = uuid, over = over})
    return true
end

return _M
