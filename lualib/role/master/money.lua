local _MAS = require "handler.master"
local awardmoney = require "role.award.money"
local award = require "role.award"
local lang = require "lang"

function _MAS.money_list(self)
    local list = {}
    for type in pairs(awardmoney) do
        table.insert(list, {
            label = lang("awardtype_" .. type),
            type = type,
            cnt = award.getcnt(self, type)
        })
    end

    return {e = 0, list = list}
end

function _MAS.money_change(self, ctx)
    local type, addcnt = tonumber(ctx.body.type), tonumber(ctx.body.cnt)
    assert(awardmoney[type] and addcnt >= 0)
    local delcnt = award.getcnt(self, type)
    local add, del = {}, {}
    if addcnt > 0 then table.insert(add, {type, 0, addcnt}) end
    if delcnt > 0 then table.insert(del, {type, 0, delcnt}) end
    assert(award.deladd(self, {flag = "MASTER"}, del, add))
    return {e = 0}
end
