-- 自身拥有指定状态
local check_or = require"battle.status".check_or
local unpack = table.unpack

return function(bctx, self, tobj, ctx, parm)
    if check_or(self, unpack(parm)) then return true end
    return false
end
