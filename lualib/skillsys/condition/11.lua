-- 概率
local b_util_random = require"battle.util".random

return function(bctx, self, tobj, ctx, parm)
    local value = parm[1]
    return b_util_random(bctx) < value
end

