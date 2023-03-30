-- 目标是否是boss
return function(bctx, self, tobj, ctx, parm)
    if not tobj then return false end
    local is_boss = parm[1]
    return is_boss == (tobj.boss or 0)
end

