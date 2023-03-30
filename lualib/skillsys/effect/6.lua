--[[
    妮可技能(在目标身后创建一个分身)
]] local find_back = require"battle.util".find_back
local add_clone = require"battle.global".add_clone
local clone = require "battle.clone"

return function(bctx, src, ctx, tobj, ecfg)
    local parm = ecfg.parm
    local skillid, max, buffid = parm[1], parm[2], parm[3]
    local parm2 = ecfg.parm2
    local atkcoe, defcoe, hpmaxcoe, hurt_val = parm2[1], parm2[2], parm2[3],
        parm2[4]

    local hex = find_back(bctx, src, tobj)
    local obj = clone(bctx, src, ctx, {
        x = hex.x,
        y = hex.y,
        attrs_coe = {atk = atkcoe, def = defcoe, hpmax = hpmaxcoe},
        combo_skill = nil,
        skilllist = {skillid},
        init_buffs = buffid and {buffid},
        from_eid = ecfg.id,
        maxnum = max,
        cfgid = src.cfgid,
        clonetype = 2,
        clone_hurtup = hurt_val
    })
    add_clone(bctx, obj)
    obj:set_target(tobj)
end
