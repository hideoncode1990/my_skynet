local skynet = require "skynet"
local hexagon = require "battle.hexagon"
local iface = require "battleiface"
local etype = require "skillsys.etype"
local cfgdata = require "cfg.data"
local random = require "battle.random"
local utime = require "util.time"
local vector2 = require "battle.vector2"
local movehex = require "battle.move_hex"
local log = require "log"
local profile = require "battle.profile"
require "util"
local _M = {}

local tag_type
skynet.init(function()
    local cfg = cfgdata.basic
    tag_type = cfg.condition_hero
end)

local function get_usable_hex(bctx, self, hex)
    local objmgr = bctx.objmgr
    if not hex or movehex.check_heroin(bctx, hex) then
        hex = objmgr.find_usable_hex(self.hex)
        if not hex then
            local size = bctx.objmgr.size
            log("%s(%d,%d) in (%d,%d)[%f,%f] replayid=%s", self.id, self.hex.hx,
                self.hex.hy, size.hx, size.hy, size.x, size.y, bctx.uuid)
            profile.show_allobjs_hex(bctx)
        end
        assert(hex)
    end
    if not hex.x then
        local pos = objmgr.to_pos(hex)
        hex.x = pos.x
        hex.y = pos.y
    end
    return hex
end

function _M.find_back(bctx, from, to)
    local hex = hexagon.find_back(bctx, from, to)
    return get_usable_hex(bctx, to, hex)
end

function _M.find_front(bctx, from, to)
    local hex = hexagon.find_front(bctx, from, to)
    return get_usable_hex(bctx, to, hex)
end

function _M.find_near(bctx, self)
    local r = _M.random(bctx)
    local hex = hexagon.rand_near(bctx, self.hex, r)
    return get_usable_hex(bctx, self, hex)
end

function _M.get_skill(cfgid, level)
    return iface.get_mon_skills(cfgid, level)
end

function _M.inherit_tag(self, tobj)
    for _, tag in ipairs(tag_type) do self[tag] = tobj[tag] end
end

function _M.get_tag_type(tag_id)
    return tag_type[tag_id]
end

function _M.random(bctx, m, n)
    local low, up
    if m == nil and n == nil then
        low, up = 0, 1000
    elseif m and n == nil then
        low, up = 0, m
    elseif m and n then
        low, up = m, n
    end
    assert(up > low)
    local v = random.rand(bctx) % (up - low)
    return v + low
end

function _M.now()
    local ti = skynet.hpc() / 1000000 -- ms 
    return ti
end

_M.time = utime.time

function _M.rand_dest(bctx, self, dir, r_min, r_max)
    local objmgr = bctx.objmgr
    local angle = _M.random(bctx, 360)
    local r = _M.random(bctx, r_min, r_max)
    dir = vector2.dir_rotate_scale(dir, angle, r)
    local dist_pos = vector2.add(self, dir)
    local size = objmgr.size
    dist_pos.x = math.max(0.1, math.min(size.x - 0.1, dist_pos.x))
    dist_pos.y = math.max(0.1, math.min(size.y - 0.1, dist_pos.y))
    local dest = objmgr.to_hex(dist_pos)
    return dest
end

function _M.genid(ctx)
    local ID = ctx.ID or 100
    ID = ID + 1
    ctx.ID = ID
    return ID
end

function _M.objmgr(bctx, fn, ...)
    local objmgr = bctx.objmgr
    return objmgr[fn](...)
end

function _M.log(bctx, fmt, ...)
    local uuid = bctx.uuid
    log(string.format("uuid=%%s frame=%%d %s", fmt), uuid, bctx.btime.frame, ...)
end

function _M.shuffle(bctx, tbl)
    for i = #tbl, 2, -1 do
        local j = (_M.random(bctx) % i) + 1
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
end

local filter = {
    battle_ctx = true,
    attrs_b = true,
    attrs_a = true,
    attrs_p = true,
    opt = true,
    skillsys_incast = true,
    buffsys_list = true,
    buffsys_ctx = true,
    baseattrs = true
}

local callback = {
    clones = function(val)
        local ret = {}
        for i, o in ipairs(val) do ret[i] = o.id end
        return ret
    end,
    attrs = function(val)
        local ret = {}
        for k, v in pairs(val) do if v ~= 0 then ret[k] = v end end
        return ret
    end
}

local function dump(obj, ...)
    local o = {}
    local s = {}
    for _, key in ipairs({...}) do s[key] = true end
    for k, v in pairs(obj) do
        if s[k] or not filter[k] then
            local cb = callback[k]
            o[k] = cb and cb(v) or v
        end
    end
    return o
end
function _M.dump_obj(obj, str, ...)
    local t = dump(obj, ...)
    ldump(t, str or "dump obj")
end

function _M.dump_objs(objs, str, ...)
    local ret = {}
    for k, obj in pairs(objs) do ret[k] = dump(obj, ...) end
    ldump(ret, str or "dump objs")
end
return _M
