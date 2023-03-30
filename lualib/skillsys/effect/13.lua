--[[
    效果分支
]] local skillsys = require "skillsys"
local condition = require "skillsys.condition"
local cast_effectlist = skillsys.cast_effectlist

local function check_cond(bctx, src, tobj, ctx, conds, ...)
    for _, c in ipairs(conds) do
        if not condition(bctx, src, tobj, ctx, c, ...) then return false end
    end
    return true
end
return function(bctx, src, ctx, tobj, ecfg, e_args)
    local e_ctx = {minhp = tobj.attrs.hp}
    local condlist = ecfg.branch_cond
    local effectlist = ecfg.branch_effect
    for i, conds in ipairs(condlist) do
        if check_cond(bctx, src, tobj, ctx, conds, e_args) then
            cast_effectlist(bctx, src, ctx, effectlist[i], tobj, tobj.x, tobj.y,
                e_ctx)
            return
        end
    end
    local default_effects = ecfg.branch_default
    if default_effects then
        cast_effectlist(bctx, src, ctx, default_effects, tobj, tobj.x, tobj.y,
            e_ctx)
    end
end

