--[[
    开始累加承受的伤害
]] return function(bctx, src, ctx, tobj, ecfg, e_args, negative_effect)
    if negative_effect then
        tobj.acc_damage = nil
    else
        tobj.acc_damage = 0
    end
end
