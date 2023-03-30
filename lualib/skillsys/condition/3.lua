-- 上阵指定特性英雄数量大于等于
local unpack = table.unpack
local get_traits_cnt = require"battle.global".get_traits_cnt
return function(bctx, self, tobj, ctx, parm)
    local tag_id, tag_v, num = unpack(parm)
    local cnt = get_traits_cnt(bctx, self, tag_id, tag_v)
    return cnt >= num
end
