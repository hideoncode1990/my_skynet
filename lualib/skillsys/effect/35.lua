--[[
    以目标为圆心随机位置产生机关
]] local add_trigger = require"battle.global".add_trigger
local etype_display<const> = require"skillsys.etype".display
local rand_dest = require"battle.util".rand_dest
local insert = table.insert
local floor = math.floor

return function(bctx, src, ctx, tobj, ecfg)
    local parm = ecfg.parm
    local trigger_id, cnt, radius = parm[1], parm[2], parm[3]
    local dir = {x = tobj.x, y = tobj.y}
    for _ = 1, cnt do
        local dist_pos = rand_dest(bctx, tobj, dir, 0, radius)
        add_trigger(bctx, trigger_id, dist_pos.x, dist_pos.y, src)
        insert(ctx.out, {
            effectid = ecfg.id,
            etype = etype_display,
            skillid = ctx.skillid,
            caster = src.id,
            target = tobj.id,
            args2 = floor(dist_pos.x * 100),
            args3 = floor(dist_pos.y * 100)
        })

    end
end
