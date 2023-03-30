--[[
    客户端表现
]] local etype = require "skillsys.etype"
local etype_display<const> = etype.display
local insert = table.insert

return function(bctx, src, ctx, tobj, ecfg)
    local parm = ecfg.parm
    local _type = parm[1]
    insert(ctx.out, {
        effectid = ecfg.id,
        etype = etype_display,
        skillid = ctx.skillid,
        caster = src.id,
        target = tobj.id,
        args1 = _type
    })
end
