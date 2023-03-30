local _MAS = require "handler.master"
local award = require "role.award"

function _MAS.item(self, ctx)
    local query = ctx.query
    local itemtype, itemid, itemcnt, e1 = query.itemtype, query.itemid,
        query.itemcnt, query.e1
    assert(itemtype > 0 and itemid >= 0 and itemcnt > 0)
    local add = {{itemtype, itemid, itemcnt, e1}}
    award.adde(self, {flag = "MASTER", theme = "MASTER CMD", content = ""}, add)
    return {e = 0}
end
