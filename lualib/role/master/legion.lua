local _MAS = require "handler.master"
local legion = require "role.m_legion_trial"
function _MAS.legion_buff(self, ctx)
    local id, cnt = ctx.query.id, ctx.query.cnt
    local e = legion.add_card(self, id, cnt)
    return {e = e}
end
