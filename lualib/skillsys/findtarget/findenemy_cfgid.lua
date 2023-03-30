--[[
    根据配置id选择敌人
]] local object_find = require "battle.object_find"
local find_target_all = object_find.find_target_all
local check = object_find.checkenemy

return function(bctx, ecfg, src, tobj, x, y)
    local args = ecfg.findtargetargs
    local cfgid = args[1]
    local ret = find_target_all(bctx, src, function(self, o)
        if cfgid ~= o.cfgid then return false end
        return check(self, o, tobj, ecfg)
    end)
    return ret
end

