local object = require "battle.object"
return function(bctx, ecfg, src, tobj, x, y)
    if not tobj then return {} end
    if object.cant_selected(tobj) then return {} end
    return {tobj}
end
