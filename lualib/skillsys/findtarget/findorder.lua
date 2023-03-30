--[[
    沿用上一段技能巡敌的结果
]] local insert = table.insert
local object = require "battle.object"
return function(bctx, ecfg, src, tobj, x, y)
    local ctx = src.skillsys_incast
    if not ctx then return {} end
    local targets = ctx.targets
    if not targets then return {} end
    local objs = {}
    for _, o in pairs(targets) do
        if not object.cant_selected(o) then insert(objs, o) end
    end
    return objs
end
