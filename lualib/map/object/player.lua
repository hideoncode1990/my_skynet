local client = require "client"
local objmgr = require "map.objmgr"
local objtype = require "map.objtype"
local env = require "map.env"
local release = require "service.release"
local trigger = require "map.trigger"
local lock = require "skynet.queue"
local supply = require "map.supply"
local gird = require "map.gird"
local cache = require("map.cache")("playerpos")
local schema = require "mongo.schema"
local log = require "log"

local selftype = objtype.player

local _M = {}

local function new(obj)
    obj.objtype = selftype
    obj.lock = lock()
    obj.pos = cache.get().pos or objmgr.born()
    return setmetatable(obj, {__index = _M})
end

function _M.pack(self)
    return "map_player", self
end

_M.pack_save = schema.OBJ {
    uuid = schema.ORI,
    pos = schema.ORI,
    objtype = schema.ORI
}

function _M.onadd()
end
function _M.ondel()
end

local function transfer_to(pos, mark)
    local ply = objmgr.player()
    ply.pos = pos
    cache.get().pos = pos
    objmgr.arrival_execute(pos)
    objmgr.clientpush("map_player_move",
        {rid = ply.uuid, pos = pos, transfer = mark})
    print("pos:", pos)
    cache.dirty()
    trigger.invoke("move", pos)
end

function _M.transfer_to(pos)
    transfer_to(pos, 1)
end

local _LUA = require "handler.lua"

local function map_enter(obj)
    local ply = objmgr.player()
    if ply then
        ply.fd = obj.fd
        client.push(ply, "map_enter", {mapid = env.mapid, pos = ply.pos})
        objmgr.reenter(ply)
    else
        ply = new(obj)
        client.push(ply, "map_enter", {mapid = env.mapid, pos = ply.pos})
        objmgr.enter(ply)
        trigger.invoke("move", ply.pos)
    end
end
function _LUA.map_enter(obj)
    print("map_enter", obj.uid, obj.rname, obj.fd)
    assert(obj.uuid == env.rid)
    local ok, err = xpcall(map_enter, debug.traceback, obj)
    if ok then
        client.push(obj, "map_enter_finish", {})
        return true
    else
        client.push(obj, "map_leave", {mapid = env.mapid, mod_nm = env.mod_nm})
        log(err)
        return false
    end
end

function _LUA.map_move(rid, pos)
    local ply = assert(objmgr.player())
    assert(rid == ply.uuid)
    local from = ply.pos
    if not supply.check() then return false, 107 end
    if not gird.isconnex(from, pos) then return false, 2 end
    transfer_to(pos)
    return true
end

-- v为false时表示obj需要删除该字段
function _LUA.map_player_infochange(tab)
    local obj = objmgr.player()
    for k, v in pairs(tab) do obj[k] = v and v or nil end
end

local function map_leave(rid)
    print("_LUA.map_leave")
    local obj = objmgr.player()
    assert(obj and obj.uuid == rid)
    client.push(obj, "map_leave", {mapid = env.mapid, mod_nm = env.mod_nm})
    objmgr.del(rid)
    return true
end

release.release("map.object.player", function()
    while true do
        local obj = objmgr.player()
        if not obj then break end

        map_leave(obj.uuid)
    end
end)

return _M
