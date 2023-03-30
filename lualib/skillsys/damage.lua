local etype = require "skillsys.etype"
local stat = require "battle.stat"
local calc = require "skillsys.calc"
local passive_type = require "skillsys.passive_type"
local _BG = require "battle.global"
local status = require "battle.status"
local status_type = require "battle.status_type"
local object = require "battle.object"

local insert = table.insert
local max = math.max

local status_type_god<const> = status_type.god
local status_type_no_hurt<const> = status_type.no_hurt
local etype_dechp_crit<const> = etype.dechp_crit
local etype_dechp<const> = etype.dechp
local passive_type_kill<const> = passive_type.kill
local status_check = status.check
local is_immune = calc.is_immune
local get_killtpv = calc.get_killtpv
local calc_tpv_by_damage = calc.calc_tpv_by_damage
local passive_trigger = _BG.passive_trigger
local stat_damage = stat.damage

local _M = {}

local function shield_absorb(bctx, src, tobj, ecfg, val, ctx)
    local magic_physical = tobj.magic_physical
    local shield, cost, left =
        object.dec_shield(bctx, tobj, val, magic_physical)
    if cost > 0 then
        insert(ctx.out, {
            effectid = ecfg.id,
            etype = etype.dec_shield,
            skillid = ctx.skillid,
            caster = src.id,
            target = tobj.id,
            args1 = cost,
            args2 = shield
        })
    end
    return left
end

local function check_immune(bctx, src, tobj, ecfg, damage, ctx)
    if status_check(tobj, status_type_god) then return true end
    -- 免疫
    if status_check(tobj, status_type_no_hurt) or is_immune(bctx, src, tobj) then
        passive_trigger(bctx, passive_type.no_hurt, tobj, src, ctx)
        insert(ctx.out, {
            effectid = ecfg.id,
            etype = etype.immune,
            skillid = ctx.skillid,
            caster = src.id,
            target = tobj.id
        })
        return true
    end
end

local function rebound_damage(bctx, src, tobj, ecfg, damage, ctx)
    if not object.can_attacked(tobj) then return end
    -- 免疫
    if check_immune(bctx, src, tobj, ecfg, damage, ctx) then return end
    damage = shield_absorb(bctx, src, tobj, ecfg, damage, ctx)
    if damage > 0 then
        local hp, isdead = object.dec_hp(bctx, tobj, damage, src, ctx)
        stat_damage(bctx, src, damage, tobj, isdead)
        insert(ctx.out, {
            effectid = ecfg.id,
            etype = etype.rebound,
            skillid = ctx.skillid,
            dead = isdead,
            caster = src.id,
            target = tobj.id,
            args1 = damage,
            args2 = hp
        })
    end
end

function _M.apply(bctx, src, tobj, ecfg, damage, ctx, opt)
    damage = max(1, damage)
    local final_d
    -- 免疫
    if check_immune(bctx, src, tobj, ecfg, damage, ctx) then return end
    final_d = damage
    damage = shield_absorb(bctx, src, tobj, ecfg, damage, ctx)
    local d = calc.calc_rebound_damage(tobj, src.magic_physical, damage)
    -- 反弹的伤害不加怒气
    if d > 0 then rebound_damage(bctx, tobj, src, ecfg, d, ctx) end
    local hp, isdead = object.dec_hp(bctx, tobj, damage, src, ctx)
    local is_crit = opt and opt.is_crit
    if damage > 0 then
        stat_damage(bctx, src, damage, tobj, isdead)
        local e_type = etype_dechp
        if is_crit then
            e_type = etype_dechp_crit
        elseif opt and opt.is_rebound then
            e_type = etype.rebound
        end
        insert(ctx.out, {
            effectid = ecfg.id,
            etype = e_type,
            skillid = ctx.skillid,
            dead = isdead,
            caster = src.id,
            target = tobj.id,
            args1 = damage,
            args2 = hp
        })
    end
    if not isdead and opt and opt.two_stage then
        -- 二段伤害
        final_d = final_d + opt.two_stage
        local two_stage_damage = shield_absorb(bctx, src, tobj, ecfg,
            opt.two_stage, ctx)
        if two_stage_damage > 0 then
            hp, isdead = object.dec_hp(bctx, tobj, two_stage_damage, src, ctx)
            stat_damage(bctx, src, two_stage_damage, tobj, isdead)
            damage = damage + two_stage_damage
            insert(ctx.out, {
                effectid = ecfg.id,
                etype = is_crit and etype_dechp_crit or etype_dechp,
                skillid = ctx.skillid,
                dead = isdead,
                caster = src.id,
                target = tobj.id,
                args1 = two_stage_damage,
                args2 = hp
            })
        end
    end
    if isdead then -- 击杀获得怒气
        if object.can_add_tpv(src) then
            passive_trigger(bctx, passive_type_kill, src, tobj, ctx)
            local val = get_killtpv(src)
            if val > 0 then
                local tpv = object.add_tpv(src, val)
                insert(ctx.out, {
                    etype = etype.killtpv,
                    skillid = ctx.skillid,
                    caster = src.id,
                    target = src.id,
                    args1 = val,
                    args2 = tpv
                })
            end
        end
    else -- 受到伤害获得怒气
        local val = calc_tpv_by_damage(tobj, damage)
        if val > 0 then
            local tpv = object.add_tpv(tobj, val)
            insert(ctx.out, {
                etype = etype.inctpv_noshow,
                skillid = ctx.skillid,
                caster = src.id,
                target = tobj.id,
                args1 = val,
                args2 = tpv
            })
        end
    end
    return final_d
end

return _M
