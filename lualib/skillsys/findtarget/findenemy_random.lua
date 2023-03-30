--[[
    全场范围内随机敌方目标
]] local object_find = require "battle.object_find"
local find_target_all = object_find.find_target_all
local check = object_find.checkenemy
local shuffle = require"battle.util".shuffle

return function(bctx, ecfg, src, tobj, x, y)
    local args = ecfg.findtargetargs
    local max = args[1]
    local list = find_target_all(bctx, src, check, tobj, ecfg)
    shuffle(bctx, list)
    local r = {}
    local cnt = 0
    for _, o in ipairs(list) do
        table.insert(r, o)
        cnt = cnt + 1
        if cnt >= max then break end
    end
    return r
end
