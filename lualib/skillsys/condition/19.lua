-- 自身被添加指定buffid
return function(bctx,self, tobj, ctx, parm, c_args)
    local buffid = c_args.buffid
    for _, id in ipairs(parm) do if buffid == id then return true end end
    return false
end
