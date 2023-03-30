--[[
圆形寻敌，以敌方为中心，半径为6的圆形范围，选择距离最近的4个目标
]] local object_find = require "battle.object_find"
local find_target_circle = object_find.find_target_circle
local check = object_find.checkfriend
local stat_push = require"battle.stat".push

return function(bctx, ecfg, src, tobj, x, y)
    local args = ecfg.findtargetargs
    local radius, max = args[1], args[2]
    local center = tobj or {x = x, y = y}
    local ret, ceils = find_target_circle(bctx, src, center, radius, max, check,
        center, ecfg)
    --[[
    if ceils then
        stat_push(bctx, src, "findtarget_circle",
            {x = center.x, y = center.y, radius = radius, ceils = ceils})
    end
    -- ]]
    return ret
end
