--[[
    添加/移除被动
]] local _BG = require "battle.global"
local passive_unload = _BG.passive_unload
local passive_load = _BG.passive_load

return function(bctx, src, ctx, tobj, ecfg, e_args, negative_effect)
    local ids = ecfg.parm
    if negative_effect then
        passive_unload(tobj, ids)
    else
        passive_load(bctx, tobj, ids)
    end
end

