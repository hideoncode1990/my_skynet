local award = require "role.award"
local awardtype = require "role.award.type"
local mods = require "role.mods"
local getupvalue = require "debug.getupvalue_recursive"
local _MAS = require "handler.master"

local mod_name = "items"

function _MAS.bag(self)
    local mod = mods.get(nil, mod_name)
    local cache = getupvalue(mod.enter, "cache")
    local list = {}
    for id, cnt in pairs(cache.get(self)) do
        table.insert(list, {id = id, cnt = cnt})
    end
    return {e = 0, list = list}
end

function _MAS.bag_change(self, ctx)
    local id, addcnt = tonumber(ctx.body.id), tonumber(ctx.body.cnt)
    local delcnt = award.getcnt(self, awardtype.items, id)
    local add, del = {}, {}
    if addcnt > 0 then table.insert(add, {awardtype.items, id, addcnt}) end
    if delcnt > 0 then table.insert(del, {awardtype.items, id, delcnt}) end
    local _, e = award.deladd(self, {flag = "MASTER"}, del, add)
    return {e = e or 0}
end
