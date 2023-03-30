-- 敌方存活英雄数量等于
local friend_hero_cnt = require"battle.global".friend_hero_cnt
return function(bctx, self, tobj, ctx, parm)
    local num = parm[1]
    local cnt = friend_hero_cnt(bctx, tobj)
    return cnt == num
end
