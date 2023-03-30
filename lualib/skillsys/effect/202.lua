--[[
添加一个trigger
]] local add_trigger = require"battle.global".add_trigger
return function(bctx, src, ctx, tobj, ecfg)
    local trigger_id = ecfg.parm[1]
    add_trigger(bctx, trigger_id, tobj.x, tobj.y, src)
end
