local skynet = require "skynet"
local _MAS = require "handler.master"

local solo_record

skynet.init(function()
    solo_record = skynet.uniqueservice("game/solo_record")
end)

function _MAS.solo()
    skynet.call(solo_record, "master", "solo_record_del")
    return {e = 0}
end
