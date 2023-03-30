-- 目标拥有指定状态
local check_or = require"battle.status".check_or
local unpack = table.unpack

return function(bctx, self, tobj, ctx, parm)
    if not tobj then return false end
    if check_or(tobj, unpack(parm)) then return true end
    return false
end

