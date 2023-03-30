--[[
扣除血量(计算伤害)
]] local calc = require "skillsys.calc"
local damage = require "skillsys.damage"
local etype = require "skillsys.etype"
local _BG = require "battle.global"
local passive_type = require "skillsys.passive_type"
local skillsys = require "skillsys"
local object = require "battle.object"

local tonumber = tonumber
local max = math.max
local min = math.min
local floor = math.floor
local insert = table.insert

local calc_damage = calc.calc_damage
local calc_two_stage_damage = calc.calc_two_stage_damage
local passive_trigger_Bi = _BG.passive_trigger_Bi
local calc_tpv_by_atk = calc.calc_tpv_by_atk
local damage_apply = damage.apply
local damage_cut = calc.damage_cut
local cast_effectlist = skillsys.cast_effectlist
local passive_after_attack<const> = passive_type.after_attack
local passive_after_hurt<const> = passive_type.after_hurt
local etype_inctpv_noshow<const> = etype.inctpv_noshow

return function(bctx, src, ctx, tobj, ecfg, e_args)
    assert(src.id ~= tobj.id, "effect 1 attack self")
    if not ecfg.no_passive_trigger then
        passive_trigger_Bi(bctx, passive_type.before_attack,
            passive_type.before_hurt, src, tobj, ctx)
    end
    local parm = ecfg.parm
    local _type = parm[1]
    local coe = tonumber(parm[2])
    local _type_args = parm[4]
    local dmg = 0
    local is_crit, opt
    if _type == 1 then -- 属性计算
        dmg, is_crit = calc_damage(bctx, ctx, src, tobj, coe / 1000)
        local two_stage = calc_two_stage_damage(src, dmg)
        opt = {two_stage = two_stage, is_crit = is_crit}
    elseif _type == 2 then -- 固定伤害
        dmg = coe
    elseif _type == 3 then -- 血量百分比
        local hpmax = tobj.attrs.hpmax
        dmg = floor(min(hpmax, max(0, hpmax * coe / 1000)))
    elseif _type == 4 then -- 传递过来的伤害
        dmg = floor(max(0, e_args.damage * coe / 1000))
        opt = {is_rebound = _type_args}
    elseif _type == 5 then -- 累加的承受伤害
        local acc_damage = floor((src.acc_damage or 0) * coe / 1000)
        dmg = floor(acc_damage)
    elseif _type == 6 then -- 溅射伤害减免
        dmg = floor(e_args.damage * coe / 1000)
        dmg = damage_cut(bctx, ctx, dmg, src, tobj)
    elseif _type == 7 then -- 同调为最低血量
        local hp = tobj.attrs.hp
        local d = floor(max(0, hp - e_args.minhp))
        dmg = floor(d * coe / 1000)
    end
    local p3 = assert(parm[3]) -- 攻击获得怒气
    if p3 > 0 and object.can_add_tpv(src) then
        local val = calc_tpv_by_atk(src, p3, is_crit)
        if val > 0 then
            local tpv = object.add_tpv(src, val)
            insert(ctx.out, {
                etype = etype_inctpv_noshow,
                skillid = ctx.skillid,
                caster = src.id,
                target = src.id,
                args1 = val,
                args2 = tpv
            })
        end
    end
    local final_d = damage_apply(bctx, src, tobj, ecfg, dmg, ctx, opt)
    if final_d and final_d > 0 then
        -- 累加受到的伤害
        if tobj.acc_damage then
            tobj.acc_damage = tobj.acc_damage + final_d
        end
        -- 附加效果
        local attach_effects = ecfg.attach_effects
        if attach_effects then
            cast_effectlist(bctx, src, ctx, attach_effects, tobj, tobj.x,
                tobj.y, {damage = final_d})
        end

        if not ecfg.no_passive_trigger then
            passive_trigger_Bi(bctx, passive_after_attack, passive_after_hurt,
                src, tobj, ctx, {is_crit = is_crit, damage = final_d})
        end
    end
end
