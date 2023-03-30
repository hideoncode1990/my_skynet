--[[
    选择战斗力最高的友方
]] local object_find = require "battle.object_find"
local find_target_all = object_find.find_target_all
local check = object_find.checkfriend
local sort = table.sort
local insert = table.insert

return function(bctx, ecfg, src, tobj, x, y)
    local args = ecfg.findtargetargs
    local max = args[1]
    local list = find_target_all(bctx, src, check, tobj, ecfg)
    sort(list, function(a, b)
        return a.zdl > b.zdl
    end)
    local cnt = 0
    local r = {}
    for _, o in ipairs(list) do
        insert(r, o)
        cnt = cnt + 1
        if cnt >= max then break end
    end
    return r
end

