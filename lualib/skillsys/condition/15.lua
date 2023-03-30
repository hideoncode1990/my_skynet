-- 指定特性的英雄数量等于
local get_traits_cnt = require"battle.global".get_traits_cnt
local unpack = table.unpack

return function(bctx, self, tobj, ctx, parm)
    local tag_id, tag_v, num = unpack(parm)
    local cnt = get_traits_cnt(bctx, self, tag_id, tag_v)
    return cnt == num
end
