-- 扣除怒气
local etype = require "skillsys.etype"
local etype_dectpv<const> = etype.dectpv
local etype_dectpv_noshow<const> = etype.dectpv_noshow

local floor = math.floor
local max = math.max
local insert = table.insert
local object = require "battle.object"

return function(bctx, src, ctx, tobj, ecfg)
    local parm = ecfg.parm
    local _type, coe, show = parm[1], parm[2], parm[3]
    local val
    if _type == 1 then -- 上限百分比
        local tpvmax = tobj.attrs.tpvmax
        val = max(0, floor(tpvmax * coe / 1000))
    elseif _type == 2 then -- 固定值
        val = coe
    else
        return
    end
    local tpv = object.dec_tpv(tobj, val)
    local e_type = show and etype_dectpv or etype_dectpv_noshow
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
