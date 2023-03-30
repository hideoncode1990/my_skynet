--[[
    强制攻击
]] return function(bctx, src, ctx, tobj, ecfg, e_args, negative_effect)
    if negative_effect then
        tobj.force_target = nil
    else
        tobj.force_target = src.id
    end
end
