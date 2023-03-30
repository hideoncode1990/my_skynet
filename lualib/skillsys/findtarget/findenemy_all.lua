--[[
    选择所有敌人
]] local object_find = require "battle.object_find"
local find_target_all = object_find.find_target_all
local check = object_find.checkenemy

return function(bctx, ecfg, src, tobj, x, y)
    local ret = find_target_all(bctx, src, check, tobj, ecfg)
    return ret
end

