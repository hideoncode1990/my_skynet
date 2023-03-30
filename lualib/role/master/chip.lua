local getupvalue = require "debug.getupvalue"
local chipbag = require "hero.chipbag"

local _MAS = require "handler.master"

function _MAS.chip_list(self)
    local cache = getupvalue(chipbag.del, "cache")

    local list = {}
    for k, v in pairs(cache.get(self)) do
        table.insert(list, {id = k, cnt = v})
    end
    return {e = 0, list = list}
end

function _MAS.chip_change(self, ctx)
    local id = tonumber(ctx.query.id)
    local cnt = tonumber(ctx.query.cnt)
    assert(cnt >= 0)
    local option = {flag = "MASTER"}

    local old_cnt = chipbag.getcnt(self, id)
    if cnt > old_cnt then
        chipbag.add(self, {[id] = cnt - old_cnt}, option)
    elseif cnt < old_cnt then
        chipbag.del(self, {[id] = old_cnt - cnt}, option)
    end
    return {e = 0}
end
