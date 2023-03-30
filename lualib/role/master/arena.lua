local skynet = require "skynet"
local _MAS = require "handler.master"

local arena_record

skynet.init(function()
    arena_record = skynet.uniqueservice("game/arena_record")
end)

function _MAS.arena()
    skynet.call(arena_record, "master", "arena_record_del")
    return {e = 0}
end
