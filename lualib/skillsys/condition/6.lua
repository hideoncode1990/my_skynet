-- 指定技能id
return function(bctx, self, tobj, ctx, parm)
    local skillid = ctx.skillid
    for _, id in ipairs(parm) do if id == skillid then return true end end
    return false
end

