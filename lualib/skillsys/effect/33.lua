--[[
    减少技能CD(特性条件)
]] local get_traits_cnt = require"battle.global".get_traits_cnt
local unpack = table.unpack
local min = math.min

return function(bctx, src, ctx, tobj, ecfg, e_args, negative_effect)
    local parm = ecfg.parm
    local _type, skillid, cd = parm[1], parm[2], parm[3]

    local parm2 = ecfg.parm2
    local tag_id, tag_v, base_v, max_n, num = unpack(parm2)
    num = num or 0

    local cnt = get_traits_cnt(bctx, src, tag_id, tag_v) - num
    if cnt > 0 then
        cnt = min(max_n, cnt)
        cd = cd + base_v * cnt
    end
    if cd > 0 then
        if negative_effect then cd = 0 - cd end
        tobj.skillsys_CDs[skillid] = _type == 1 and (0 - cd) or cd
    end
end

