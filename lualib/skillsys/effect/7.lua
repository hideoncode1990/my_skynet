--[[
    直接死亡
]] local etype = require "skillsys.etype"
local etype_die<const> = etype.die
local insert = table.insert
local object = require "battle.object"

return function(bctx, src, ctx, tobj, ecfg)
    object.set_dead(bctx, tobj, src, ctx, false, "effect 7")
    insert(ctx.out, {
        effectid = ecfg.id,
        etype = etype_die,
        skillid = ctx.skillid,
        dead = true,
        caster = src.id,
        target = tobj.id
    })
end
