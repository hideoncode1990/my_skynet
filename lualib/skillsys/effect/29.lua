--[[
    清除减益/增益buff
]] local del_by_type = require"skillsys.buffsys".del_by_type
return function(bctx, src, ctx, tobj, ecfg)
    local parm = ecfg.parm
    local _type, max = parm[1], parm[2]
    if max == 0 then max = nil end
    del_by_type(bctx, tobj, _type, max, ctx)
end

