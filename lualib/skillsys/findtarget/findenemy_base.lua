local object = require "battle.object"
return function(bctx, _, src, tobj, _x, _y, ctx)
    local id = ctx and ctx.objid
    if not id then return {} end
    local o = bctx.objmgr.get(id)
    if not o then return {} end
    if not object.can_attacked(o) then return {} end
    return {o}
end
