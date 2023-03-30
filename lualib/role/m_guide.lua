local cache = require("mongo.role")("guides")
local client = require "client"
local _H = require "handler.client"
local platlog = require "platlog"
local ubit = require "util.bit"
local flowlog = require "flowlog"
local NM<const> = "guide"
local _M = {}

require("role.mods") {
    name = NM,
    enter = function(self)
        client.push(self, "guide_info", {list = cache.get(self)})
    end
}

local function set(self, id)
    assert(id >= 1 and id <= 1000)
    local C = cache.get(self)
    if ubit.set(C, id) then
        cache.dirty(self)
        return 0
    end
    return 1
end

function _H.guide_set(self, msg)
    return {e = set(self, msg.id)}
end

function _H.guide_log(self, msg)
    local type = assert(msg.type)
    local id = assert(msg.id)
    flowlog.role(self, NM, {type = type, id = id})
    platlog("newstages", {event_id = type, step_level = id, is_force = 1}, self)
    return {e = 0}
end

return _M
