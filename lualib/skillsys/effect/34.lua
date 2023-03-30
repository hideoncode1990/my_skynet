--[[
    瞬移到敌人身后
]] local etype = require "skillsys.etype"
local skillsys = require "skillsys"
local b_util = require "battle.util"
local break_cast = skillsys.break_cast
local find_back = b_util.find_back
local insert = table.insert
local floor = math.floor
local stop_move = require"battle.move".stop_move

local etype_blink<const> = etype.blink

return function(bctx, src, ctx, tobj, ecfg)
    local dist_pos = find_back(bctx, src, tobj)
    break_cast(bctx, src)
    bctx.objmgr.setpos(bctx, src, dist_pos)
    stop_move(bctx, src)
    src:set_target(tobj)
    insert(ctx.out, {
        effectid = ecfg.id,
        etype = etype_blink,
        skillid = ctx.skillid,
        caster = src.id,
        target = src.id,
        args2 = floor(dist_pos.x * 100),
        args3 = floor(dist_pos.y * 100)
    })
end
