local ubit = require "util.bit"
local client = require "client.mods"
local cache = require("mongo.role")("handbook")

local NM<const> = "handbook"

local _M = {}

require("hero.mod").reg {
    name = NM,
    enter = function(self)
        client.enter(self, NM, "handbook_info", {info = cache.get(self)})
    end
}

function _M.add(self, tab)
    assert(tab <= 999)
    local C = cache.get(self)
    if ubit.set(C, tab) then
        cache.dirty(self)
        client.push(self, NM, "handbook_add", {tab = tab})
        return true
    end
end

function _M.check(self, tab)
    local C = cache.get(self)
    return ubit.get(C, tab)
end

return _M
