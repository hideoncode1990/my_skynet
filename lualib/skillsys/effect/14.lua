-- 献祭生命
local etype = require "skillsys.etype"
local stat = require "battle.stat"
local etype_dechp_noshow<const> = etype.dechp_noshow
local stat_heal = stat.heal
local insert = table.insert
local floor = math.floor
local min = math.min
local object = require "battle.object"

return function(bctx, src, ctx, tobj, ecfg)
    local parm = ecfg.parm
    local _type, coe = parm[1], parm[2]
    local val
    local nowhp = tobj.attrs.hp
    if _type == 1 then -- 当前生命百分比
        val = min(nowhp - 1, floor(nowhp * coe / 1000))
    elseif _type == 2 then -- 生命上限百分比
        local hpmax = tobj.attrs.hpmax
        val = min(nowhp - 1, floor(hpmax * coe / 1000))
    end
    local hp, isdead = object.dec_hp(bctx, tobj, val, src, ctx)
    stat_heal(src, val, tobj)
    insert(ctx.out, {
        effectid = ecfg.id,
        etype = etype_dechp_noshow,
        skillid = ctx.skillid,
        dead = isdead,
        caster = src.id,
        target = tobj.id,
        args1 = val,
        args2 = hp
    })
end

