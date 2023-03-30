--[[
    克隆英雄
]] local b_util = require "battle.util"
local add_clone = require"battle.global".add_clone
local clone = require "battle.clone"
local find_back = b_util.find_back
local find_front = b_util.find_front
local find_near = b_util.find_near
local get_skill = b_util.get_skill
local unpack = table.unpack

return function(bctx, src, ctx, tobj, ecfg)
    local _type, max, buffid = unpack(ecfg.parm)
    local atkcoe, defcoe, hpmaxcoe, hurt_val = unpack(ecfg.parm2)

    local hex
    if _type == 1 then
        hex = find_back(bctx, src, tobj)
    elseif _type == 2 then
        hex = find_front(bctx, src, tobj)
    else
        hex = find_near(bctx, tobj)
    end
    local cfgid = tobj.cfgid
    local _, skills = get_skill(cfgid, src.level)
    local obj = clone(bctx, src, ctx, {
        x = hex.x,
        y = hex.y,
        attrs_coe = {atk = atkcoe, def = defcoe, hpmax = hpmaxcoe},
        combo_skill = nil,
        skilllist = skills,
        init_buffs = buffid and {buffid},
        from_eid = ecfg.id,
        maxnum = max,
        cfgid = cfgid,
        clonetype = 1,
        clone_hurtup = hurt_val
    })
    add_clone(bctx, obj)
end
