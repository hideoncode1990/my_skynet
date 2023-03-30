--[[
    百分比掉血更改属性
]] local get_traits_cnt = require"battle.global".get_traits_cnt
local skillsys = require "skillsys"
local cast_effectlist = skillsys.cast_effectlist
local min = math.min
local modf = math.modf
local unpack = table.unpack

return function(bctx, src, ctx, tobj, ecfg, e_args)
    local parm = ecfg.parm
    local permillage, def_opps = parm[1] / 1000, (parm[2] or 1000) / 1000

    local hpmax = src.attrs.hpmax
    local prior_opps = e_args.prior_hp / hpmax
    local now_opps = src.attrs.hp / hpmax

    local parm2 = ecfg.parm2
    local start_opps
    if parm2 then
        local tag_id, tag_v, num, start_hp1, start_hp2 = unpack(parm2)
        local cnt = get_traits_cnt(bctx, src, tag_id, tag_v)
        if cnt < num then
            start_opps = start_hp1 / 1000
        else
            start_opps = start_hp2 / 1000
        end
    end
    start_opps = start_opps or def_opps
    if prior_opps >= start_opps and now_opps >= start_opps then return end
    now_opps = min(start_opps, now_opps)

    local stage = modf((start_opps - now_opps) / permillage)
    cast_effectlist(bctx, src, ctx, ecfg.attach_effects, tobj, tobj.x, tobj.y,
        {attr_multi = stage, attr_ex_m = "hpchg"})
end
