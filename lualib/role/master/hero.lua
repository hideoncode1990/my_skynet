local getupvalue = require "debug.getupvalue"
local hero = require "hero"
local hattrs = require "hero.attrs"
local copy = require("util.table").copy

local _MAS = require "handler.master"

local function mod(self)
    return assert(require("role.mods").get(self, "hero_init"))
end

function _MAS.hero_list(self)
    local cache = getupvalue(mod(self).enter, "cache")
    local list = {}
    for _, _hero in pairs(cache.get(self)) do
        local hero_copy = copy(_hero)
        local attrs, zdl = hattrs.query(self, _hero.uuid)
        hero_copy.attrs = attrs
        hero_copy.zdl = zdl
        table.insert(list, hero_copy)
    end
    return {e = 0, list = list}
end

function _MAS.hero_del(self, ctx)
    local num = getupvalue(hero.isfull, "num")
    if num <= 1 then return {e = 1, m = "the last hero can not be deleted"} end

    local uuid = tonumber(ctx.query.uuid)
    hero.dels(self, {uuid}, {flag = "MASTER"})
    return {e = 0}
end
