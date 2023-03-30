--[[
    在上一段技能巡敌的结果中随机
]] local insert = table.insert
local object = require "battle.object"
local shuffle = require"battle.util".shuffle
return function(bctx, ecfg, src, tobj, x, y)
    local ctx = src.skillsys_incast
    if not ctx then return {} end
    local targets = ctx.targets
    if not targets then return {} end
    local list = {}
    for _, o in pairs(targets) do
        if not object.cant_selected(o) then insert(list, o) end
    end
    shuffle(bctx, list)
    local args = ecfg.findtargetargs
    local max = args[1]
    local r, cnt = {}, 0
    for _, o in ipairs(list) do
        insert(r, o)
        cnt = cnt + 1
        if cnt >= max then break end
    end
    return r
end
