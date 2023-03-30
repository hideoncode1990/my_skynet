local getupvalue = require "debug.getupvalue"
local eqbag = require "hero.eqbag"

local _MAS = require "handler.master"

function _MAS.equip_list(self)
    local cache = getupvalue(eqbag.dels, "cache")

    local list = {}
    for _, v in pairs(cache.get(self)) do table.insert(list, v) end
    return {e = 0, list = list}
end

function _MAS.equip_del(self, ctx)
    local uuid = tonumber(ctx.query.uuid)
    eqbag.dels(self, {uuid}, {flag = "MASTER"})
    return {e = 0}
end
