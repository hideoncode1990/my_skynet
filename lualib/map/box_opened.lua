local utable = require "util.table"
local cache = require("map.cache")("box_opened")
local event_listen = require "event_listen"
local env = require "map.env"
local schema = require "mongo.schema"

cache.schema(schema.SET())

local function list()
    return env.boxlist or cache.get()
end

local _M = {}
function _M.check(uuid)
    return list()[uuid]
end

function _M.add(o)
    local uuid = o.uuid
    if env.boxlist then
        env.boxlist[uuid] = true
        event_listen("box_open", {uuid = o.uuid, id = o.id, box = o.box})
    else
        cache.get()[uuid] = true
        cache.dirty()
    end
end

function _M.logic(para)
    return utable.logic(list(), para)
end

return _M
