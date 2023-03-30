--[[
    修改血量
]] local max = math.max
local floor = math.floor

return function(bctx, src, ctx, tobj, ecfg, e_args)
    local parm = ecfg.parm
    local _type, val = parm[1], parm[2]
    local attrs = tobj.attrs
    local hp
    if _type == 1 then
        hp = max(1, val)
    elseif _type == 2 then
        hp = max(1, floor(attrs.hpmax * val / 1000))
    elseif _type == 3 then
        hp = assert(e_args.prior_hp)
    end
    attrs.hp = hp
end
