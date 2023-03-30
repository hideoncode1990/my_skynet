--[[
    打断技能
]] local break_cast = require("skillsys").break_cast
local object = require "battle.object"
return function(bctx, src, ctx, tobj)
    if object.cant_controlled(tobj) then return end
    break_cast(bctx, tobj)
end
