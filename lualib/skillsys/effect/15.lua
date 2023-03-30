--[[
    开始随机移动
]] local battlemove = require "battle.move"
local stop_move = battlemove.stop_move
local clear_randcfg = battlemove.clear_randcfg
local break_cast = require"skillsys".break_cast

return function(bctx, src, ctx, tobj, ecfg, e_args, negative_effect)
    if negative_effect then
        clear_randcfg(tobj)
        stop_move(bctx, tobj)
    else
        break_cast(bctx, tobj)
        clear_randcfg(tobj)
        stop_move(bctx, tobj)
        tobj:on_randmove(bctx, ecfg.parm)
    end
end

