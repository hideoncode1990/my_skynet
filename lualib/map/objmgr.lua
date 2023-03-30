local skynet = require "skynet"
local client = require "client"
local gird = require "map.gird"
local cfgproxy = require "cfg.proxy"
local objtype = require "map.objtype"
local queue = require "skynet.queue"
local cache = require("map.cache")("objmgr")
local schema = require "mongo.schema"
local mods = require "map.mods"

local _M = {}
local lock = queue()

local born
local player
local objs = {}

local pos2obj = {}

local classify = setmetatable({}, {
    __index = function(t, k)
        local v = {}
        t[k] = v
        return v
    end
})

local CLASS = {}

cache.schema(schema.MAPF("uuid", function(encode, d)
    if encode then
        return d.pack_save and d.pack_save(encode, d) or d
    else
        return _M.recreate(d)
    end
end))

mods {
    name = "objmgr",
    init = function(ctx)
        local cfg = cfgproxy("scenemap")
        cfg = cfg[ctx.mapid]
        local stop = assert(cfg.stop)
        gird.init(stop .. ".stop")
        born = cfg.born
    end,
    load = function(ctx)
        objs = cache.get()
    end
}

function _M.born()
    print(born)
    assert(gird.check(born), "born point has a object")
    return born
end

local function enter(ply)
    _M.add(ply)
    player = ply
    for _, obj in pairs(objs) do _M.clientpush(obj:pack()) end
    mods.enter(ply)
end

local function reenter(ply)
    for _, obj in pairs(objs) do _M.clientpush(obj:pack()) end
    mods.enter(ply)
end

function _M.reenter(ply)
    lock(reenter, ply)
end

function _M.enter(ply)
    lock(enter, ply)
end

function _M.player()
    return player
end

function _M.clientpush(cmd, msg)
    if player then client.push(player, cmd, msg) end
end

function _M.agent_send(cmd, ...)
    skynet.send(player.addr, "lua", cmd, ...)
end
function _M.agent_call(cmd, ...)
    return skynet.call(player.addr, "lua", cmd, ...)
end

function _M.add(o)
    local uuid, tp = o.uuid, o.objtype
    if objs then objs[uuid] = o end -- recreate 时，objs没有
    if o.onadd then o:onadd() end
    if tp ~= objtype.player then
        local pos = o.pos
        local old = pos2obj[pos]
        if old then
            error(string.format(
                "the pos(%s) has existed a obj(uuid:%s) when add a new obj(uuid:%s)",
                pos, old.uuid, uuid))
        end
        pos2obj[pos] = o
        classify[tp][uuid] = o
    else
        _M.arrival_execute(o.pos)
    end
    _M.clientpush(o:pack())
    cache.dirty()
end

function _M.check_obj(uuid)
    return objs[uuid]
end

function _M.del(uuid, arg)
    print("del:", uuid, arg)
    local o = objs[uuid]
    local pos = o.pos
    objs[uuid] = nil
    pos2obj[pos] = nil
    classify[o.objtype][uuid] = nil
    if player and player.uuid == uuid then player = nil end
    if o.ondel then o:ondel() end
    _M.clientpush("map_object_del", {uuid = uuid, arg = arg})
    cache.dirty()
end

local function grab(uuid, tp)
    local o = objs[uuid]
    if o and tp then
        local otype = o.objtype
        assert(tp == otype)
    end
    return o
end

function _M.classify(tp)
    return classify[tp]
end

local function onadd(self)
    gird.stop(self.pos)
end

local function ondel(self)
    gird.unstop(self.pos)
end

function _M.class(type, class)
    class = class or {}
    CLASS[type] = class
    if not class.onadd then class.onadd = onadd end
    if not class.ondel then class.ondel = ondel end
    return class
end

function _M.create(type, ...)
    local class = CLASS[type]
    local o = class.new(...)
    if o then
        o.objtype = type
        setmetatable(o, {__index = class})
        _M.add(o)
    end
end

function _M.recreate(d)
    local type = d.objtype
    local class = CLASS[type]
    if not class then return end
    local o = assert(class.renew(d))
    o.objtype = type
    setmetatable(o, {__index = class})
    _M.add(o)
    return o
end

function _M.remove(uuid)
    _M.del(uuid)
end

function _M.arrival_execute(pos)
    local o = pos2obj[pos]
    if o and o.arrival then skynet.fork(o.arrival, o) end
end

function _M.be_shot(pos)
    local o = pos2obj[pos]
    if o and o.be_shot then skynet.fork(o.be_shot, o) end
end

-- 或且关系判定
function _M.logic(condi, tp, checkfunc)
    for _, args in ipairs(condi) do
        local ret = true
        for _, uuid in ipairs(args) do
            local o = grab(uuid, tp)
            if not o or not checkfunc(o) then
                ret = false
                break
            end
        end
        if ret then return true end
    end
    return false
end

_M.dirty = cache.dirty
_M.grab = grab

return _M
