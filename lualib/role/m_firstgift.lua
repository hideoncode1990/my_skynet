local skynet = require "skynet"
local cache = require("mongo.role")("firstgift")
local cfgproxy = require "cfg.proxy"
local award = require "role.award"

local BASIC
skynet.init(function()
    BASIC = cfgproxy("basic")
end)

require("role.mods") {
    name = "firstgift",
    load = function(self)
        local C = cache.get(self)
        if not C.give then
            C.give = 1
            cache.dirty(self)
            assert(award.add(self, {flag = "firstgift"}, BASIC.initial_gift))
        end
    end
}
