-- 增加怒气
local etype = require "skillsys.etype"
local etype_inctpv<const> = etype.inctpv
local etype_inctpv_noshow<const> = etype.inctpv_noshow

local floor = math.floor
local max = math.max
local insert = table.insert
local object = require "battle.object"

return function(bctx, src, ctx, tobj, ecfg)
    local parm = ecfg.parm
    local _type, coe, show = parm[1], parm[2], parm[3]
    local val
    if _type == 1 then -- 百分比
        local tpvmax = tobj.attrs.tpvmax
        val = max(0, floor(tpvmax * coe / 1000))
    elseif _type == 2 then -- 固定值
        val = coe
    else
        return
    end
    local e_type = show and etype_inctpv or etype_inctpv_noshow
    local tpv = object.add_tpv(tobj, val)
    insert(ctx.out, {
        effectid = ecfg.id,
        etype = e_type,
        skillid = ctx.skillid,
        caster = src.id,
        target = tobj.id,
        args1 = val,
        args2 = tpv
    })
end
