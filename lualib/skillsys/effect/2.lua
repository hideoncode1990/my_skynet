-- 回血
local etype = require "skillsys.etype"
local calc = require "skillsys.calc"
local stat = require "battle.stat"
local status = require "battle.status"
local status_type = require "battle.status_type"
local _BG = require "battle.global"
local ptype = require "skillsys.passive_type"
local ptype_attrheal<const> = ptype.attr_heal
local ptype_heal<const> = ptype.heal
local ptype_overhp<const> = ptype.overhp
local etype_inchp<const> = etype.inchp
local status_type_noheal<const> = status_type.no_heal

local passive_attr = _BG.passive_attr
local passive_trigger = _BG.passive_trigger
local calc_hp_by_atk = calc.calc_hp_by_atk
local calc_hp_fixed = calc.calc_hp_fixed
local calc_hp_percent = calc.calc_hp_percent
local calc_hp_p_lost = calc.calc_hp_p_lost
local floor = math.floor
local max = math.max
local insert = table.insert
local stat_heal = stat.heal
local status_check = status.check
local object = require "battle.object"

return function(bctx, src, ctx, tobj, ecfg, e_args)
    if status_check(tobj, status_type_noheal) then return end
    local parm = ecfg.parm
    local _type, coe = parm[1], parm[2]
    local val, is_heal
    local p_attrs = passive_attr(bctx, ptype_attrheal, src, tobj, ctx)
    if _type == 1 then -- 攻击力百分比
        val = calc_hp_by_atk(src, tobj, coe, p_attrs)
        is_heal = true
    elseif _type == 2 then -- 固定回血
        val = calc_hp_fixed(src, coe, p_attrs)
        is_heal = true
    elseif _type == 3 then -- 血量上限百分比
        val = calc_hp_percent(src, tobj, coe)
        is_heal = true
    elseif _type == 4 then -- 传递的伤害
        val = floor(max(0, e_args.damage * coe / 1000))
    elseif _type == 5 then -- 累加承受的伤害转化
        val = floor((src.acc_damage or 0) * coe / 1000)
    elseif _type == 6 then -- 已损失生命百分比
        val = calc_hp_p_lost(tobj, coe)
    else
        return
    end
    local hp, overhp = object.add_hp(bctx, tobj, val, src, ctx)
    stat_heal(src, val, tobj)
    insert(ctx.out, {
        effectid = ecfg.id,
        etype = etype_inchp,
        skillid = ctx.skillid,
        caster = src.id,
        target = tobj.id,
        args1 = val,
        args2 = hp
    })
    if is_heal then
        passive_trigger(bctx, ptype_heal, src, tobj, ctx,
            {buff_ctx = {heal = val}})
    end
    if overhp then
        passive_trigger(bctx, ptype_overhp, src, tobj, ctx,
            {buff_ctx = {overhp = overhp}})
    end
end
