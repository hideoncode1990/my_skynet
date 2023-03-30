local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local objmgr = require "map.objmgr"
local objtype = require "map.objtype"
local chat = require "map.chat"
local supply = require "map.supply"
local bag = require "map.bag"
local selftype = require("map.objtype").npc
local gird = require "map.gird"
local _LUA = require "handler.lua"

local _M = objmgr.class(selftype)

local CFG
skynet.init(function()
    CFG = cfgproxy("object_npc")
end)

function _M.new(uuid, id, pos)
    return {id = id, pos = pos, uuid = uuid}
end

function _M.renew(o)
    return o
end

function _M.pack(self)
    return "map_npc", self
end

function _LUA.map_npc(rid, uuid)
    if not supply.check() then return false, 107 end
    local ply = objmgr.player()
    assert(rid == ply.uuid)
    local o = objmgr.grab(uuid, objtype.npc)
    if not gird.isneibo(ply.pos, o.pos) then return false, 5 end
    local cfg = CFG[o.id]
    local cfg_chat = cfg.chat
    local chat_id

    if not cfg.type then
        chat_id = cfg_chat[1]
    elseif cfg.type == chat.item_type.receive then
        local need_do, doing, done = cfg_chat[1], cfg_chat[2], cfg_chat[3]
        local item = chat.check_item(doing)
        assert(doing and item)
        if chat.check_played(doing) then
            chat_id = assert(done)
        else
            if bag.check_del({item}) then
                chat_id = doing
            else
                chat_id = assert(need_do)
            end
        end
    elseif cfg.type == chat.item_type.give then
        local doing, done = cfg_chat[1], cfg_chat[2]
        local item = chat.check_item(doing)
        assert(doing and item)
        if chat.check_played(doing) then
            chat_id = assert(done)
        else
            chat_id = assert(doing)
        end
    end
    assert(chat.start(chat_id, chat.type.initiative))
    return true
end

return _M
