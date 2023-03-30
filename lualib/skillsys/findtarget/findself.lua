--[[
以施法者自身为目标
]] local object = require "battle.object"
return function(bctx, ecfg, src, tobj, x, y)
    if not src then return {} end
    if object.is_dead(src) then return {} end
    return {src}
end
