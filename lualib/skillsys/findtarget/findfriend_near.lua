--[[
    选择最近的友方单位
]] local object_find = require "battle.object_find"
local find_target_all = object_find.find_target_all
local check = object_find.checkfriend
local vector2_distance = require"battle.vector2".distance
local sort = table.sort
local insert = table.insert

return function(bctx, ecfg, src, tobj, x, y)
    local args = ecfg.findtargetargs
    local max = args and args[1] or 1
    local list = find_target_all(bctx, src, check, tobj, ecfg)
    -- 自己放在最后面
    local max_d = math.maxinteger
    sort(list, function(a, b)
        local d1 = src.id == a.id and max_d or vector2_distance(src, a)
        local d2 = src.id == b.id and max_d or vector2_distance(src, b)
        return d1 < d2
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

