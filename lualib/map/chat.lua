local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local _LUA = require "handler.lua"
local cache = require("map.cache")("chat")
local trigger = require "map.trigger"
local objmgr = require "map.objmgr"
local target = require "map.target"
local bag = require "map.bag"
local schema = require "mongo.schema"

local ttype = {initiative = -1, passive = -2}
local item_type = {receive = 1, give = 2}

local _M = {}

local CFG
skynet.init(function()
    CFG = cfgproxy("chats")
end)

cache.schema(schema.SAR())

require("map.mods") {
    name = "chat",
    enter = function()
        for id, v in pairs(cache.get()) do
            if v and v == ttype.passive then
                print("map_chat_start", id)
                objmgr.clientpush("map_chat_start", {id = id})
            end
        end
    end
}

_M.type = ttype
_M.item_type = item_type

function _M.check_playing(id)
    return cache.get()[id]
end

function _M.check_played(id)
    return cache.get()[id] == false
end

function _M.check_item(id)
    return CFG[id].item
end

function _M.start(id, tp)
    local C = cache.get()
    C[id] = tp
    cache.dirty()
    objmgr.clientpush("map_chat_start", {id = id})
    return true
end

local function execute(cfg)
    if not cfg then return true end
    local item, tp = cfg.item, cfg.type
    assert(item and tp)
    if tp == item_type.give then
        bag.add({item})
        return true
    elseif tp == item_type.receive then
        return bag.del({item})
    end
    assert(false)
end

function _LUA.map_chat_over(rid, id, index)
    local ply = objmgr.player()
    assert(ply.uuid == rid)
    local C = cache.get()
    local tp = C[id]
    -- 如果是要给东西或扣东西的对话且以前完成过，就不能完成
    -- 其他对话可以反复完成
    if CFG[id] and not tp then return false, 11 end
    if not execute(CFG[id]) then return false, 12 end
    C[id] = false
    cache.dirty()
    target.finish(target.type.chat, id)
    trigger.invoke("chat_over", id, index)
    return true
end

return _M
