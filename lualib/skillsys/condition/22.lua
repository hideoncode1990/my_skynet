-- 是否是英雄
local object = require "battle.object"
local is_self<const> = 0
local is_target<const> = 1
return function(bctx, self, tobj, ctx, parm)
    local _type = parm[1] or 0
    if _type == is_self then
        return object.check_hero(self)
    elseif _type == is_target then
        return object.check_hero(tobj)
    end
    return false
end

