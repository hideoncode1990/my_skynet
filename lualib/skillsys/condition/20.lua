-- 与目标距离大于等于
local vector2_distance = require"battle.vector2".distance

return function(bctx, self, tobj, ctx, parm)
    local dis = parm[1] / 100
    local d = vector2_distance(self, tobj)
    return d >= dis
end
