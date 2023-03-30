--[[
    全场范围内血量最少敌方目标
]] local object_find = require "battle.object_find"
local find_target_all = object_find.find_target_all
local check = object_find.checkenemy
local sort = table.sort
local insert = table.insert
return function(bctx, ecfg, src, tobj, x, y)
    local args = ecfg.findtargetargs
    local max = args[1]
    local list = find_target_all(bctx, src, check, tobj, ecfg)
    sort(list, function(a, b)
        return a.attrs.hp < b.attrs.hp
    end)
    local r = {}
    local cnt = 0
    for _, o in ipairs(list) do
        insert(r, o)
        cnt = cnt + 1
        if cnt >= max then break end
    end
    return r
end
