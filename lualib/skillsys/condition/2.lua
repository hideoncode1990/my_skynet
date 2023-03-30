-- 暴击
return function(bctx, self, tobj, ctx, parm, c_args)
    local iscrit = c_args.is_crit
    if iscrit then return true end
    return false
end

