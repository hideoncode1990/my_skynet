local client = require "client"
local cache = require("mongo.role")("spinesetting")
local _H = require "handler.client"

local NM<const> = "spinesetting"

require("role.mods") {
    name = NM,
    enter = function(self)
        client.push(self, "spinesetting_info", cache.get(self))
    end
}

function _H.spinesetting(self, msg)
    local C = cache.get(self)
    local anim = msg.spine_anim or ""
    assert(#anim < 16)

    for k in pairs(C) do if not msg[k] then C[k] = nil end end
    for k, v in pairs(msg) do C[k] = v end
    cache.dirty(self)
    return {e = 0}
end
