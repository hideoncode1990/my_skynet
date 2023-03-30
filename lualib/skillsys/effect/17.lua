--[[
    水之穿梭(跃起穿入地下，冲至敌人身后,如果有trigger_id,路径上产生地毯）
]] local floor = math.floor
local insert = table.insert
local add_trigger = require"battle.global".add_trigger
local find_back = require"battle.util".find_back
local stop_move = require"battle.move".stop_move

local etype_water_shuttle<const> = require"skillsys.etype".water_shuttle

return function(bctx, src, ctx, tobj, ecfg)
    if ecfg.parm then
        add_trigger(bctx, ecfg.parm[1], src.x, src.y, src, tobj)
    end

    local hex = find_back(bctx, src, tobj)
    local dist_pos = hex
    local objmgr = bctx.objmgr
    local _, stop_pos = objmgr.check_line(src, dist_pos)
    if stop_pos then dist_pos = stop_pos end
    objmgr.setpos(bctx, src, dist_pos)
    stop_move(bctx, src)
    insert(ctx.out, {
        effectid = ecfg.id,
        etype = etype_water_shuttle,
        skillid = ctx.skillid,
        caster = src.id,
        target = src.id,
        args2 = floor(dist_pos.x * 100),
        args3 = floor(dist_pos.y * 100)
    })
end
