--[[
    护盾(添加/移除)
]] local etype = require "skillsys.etype"
local calc = require "skillsys.calc"
local calc_shield_by_atk = calc.calc_shield_by_atk
local calc_shield_by_hpmax = calc.calc_shield_by_hpmax
local floor = math.floor
local abs = math.abs
local insert = table.insert
local object = require "battle.object"

local etype_dec_shield<const> = etype.dec_shield
local etype_add_shield<const> = etype.add_shield

return function(bctx, src, ctx, tobj, ecfg, e_args, negative_effect)
    local buff_uuid = e_args.buff_uuid
    if not buff_uuid then return end
    local parm = ecfg.parm
    local _type, coe = parm[1], parm[2]
    local val
    if _type == 1 then -- 攻击百分比
        val = calc_shield_by_atk(src, coe / 1000)
    elseif _type == 2 then -- 固定值
        val = coe
    elseif _type == 3 then -- 血量百分比
        val = calc_shield_by_hpmax(src, coe / 1000)
    elseif _type == 4 then -- 过量治疗
        val = floor(e_args.buff_ctx.overhp * coe / 1000)
    elseif _type == 5 then -- 治疗量的百分比
        val = floor(e_args.buff_ctx.heal * coe / 1000)
    else
        return
    end
    local shield_type = parm[3]
    local shield, optype
    if negative_effect then
        optype = etype_dec_shield
        val, shield = object.remove_shield(bctx, tobj, buff_uuid)
    else
        optype = etype_add_shield
        val, shield = object.add_shield(bctx, tobj, buff_uuid, val, shield_type)
    end
    if abs(val) > 0 then
        insert(ctx.out, {
            effectid = ecfg.id,
            etype = optype,
            skillid = ctx.skillid,
            caster = src.id,
            target = tobj.id,
            args1 = val,
            args2 = shield
        })
    end
end
