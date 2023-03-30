local skynet = require "skynet"
local cfgdata = require "cfg.data"
local attrpara = require"util.attrs".para
local b_util = require "battle.util"
local ptype = require "skillsys.passive_type"
local _BG = require "battle.global"
local _M = {}
local CFG, LEVEL_DIFF_CFG
skynet.init(function()
    CFG, LEVEL_DIFF_CFG = cfgdata.battle, cfgdata.battle_level_diff
end)

local ulog = b_util.log
local function log(bctx, self, ...)
    ulog(bctx, ...)
end

local max = math.max
local min = math.min
local floor = math.floor
local abs = math.abs
local b_util_random = b_util.random
local passive_attr = _BG.passive_attr

local function isnan(x)
    return x ~= x
end
-- 命中率 = 系数1 + 进攻方命中- 防御方闪避
function _M.get_hit_opps(caster, target, generic_skill)
    local cattrs, tattrs = caster.attrs, target.attrs
    local hit = CFG.init_hit + cattrs.hit / attrpara.hit - tattrs.dodge /
                    attrpara.dodge
    if generic_skill then hit = hit * (1 - cattrs.blind / attrpara.blind) end
    return max(0, hit)
end

function _M.is_immune(bctx, caster, target)
    local tattrs = target.attrs
    local magic_physical = caster.magic_physical
    local key = "immune_" .. magic_physical
    local opps = tattrs[key]
    if b_util_random(bctx) > opps then return false end
    return true
end

local function get_critdm(bctx, caster, target, p_cattrs, p_tattrs)
    -- 暴击率 = 系数1 + 进攻方暴击- 防御方韧性
    local cattrs, tattrs = caster.attrs, target.attrs
    local crit = cattrs.crit + (p_cattrs and p_cattrs.crit or 0)
    local tough = tattrs.tough + (p_tattrs and p_tattrs.tough or 0)
    crit = CFG.init_crit + crit / attrpara.crit - tough / attrpara.tough
    crit = max(0, crit)
    if b_util_random(bctx) / 1000 > crit then return false, 0 end
    -- 暴击伤害加成 = 系数1+ 进攻方暴击伤害- 防御方暴伤减免
    local critdm = cattrs.critdm + (p_cattrs and p_cattrs.critdm or 0)
    local critdmredu = tattrs.critdmredu +
                           (p_tattrs and p_tattrs.critdmredu or 0)
    critdm = CFG.init_critdm + critdm / attrpara.critdm - critdmredu /
                 attrpara.critdmredu
    return true, min(CFG.critdm_max, max(CFG.critdm_min, critdm))
end

-- 减伤
local function calc_dmcut(bctx, caster, target, p_tattrs)
    local tattrs = target.attrs
    local feature, dm_type, magic_physical = caster.feature, caster.dm_type,
        caster.magic_physical
    -- 伤害减免系数 = （1-伤害减免）*（1-英雄能力类型伤害减免）*（1-英雄伤害类型伤害减免) * (1 - 受到的物理/法系伤害减少)
    local cut_fn = "dmcut_features_" .. feature
    local cut_tn = "dmcut_type_" .. dm_type
    local cut_mag_phy = "dmcut_mag_phy_" .. magic_physical
    local p_dmcut = p_tattrs and p_tattrs.dmcut or 0
    local dmcut = (1 - (tattrs.dmcut + p_dmcut) / attrpara.dmcut) *
                      (1 - tattrs[cut_fn] / attrpara[cut_fn]) *
                      (1 - tattrs[cut_tn] / attrpara[cut_tn]) *
                      (1 - tattrs[cut_mag_phy] / attrpara[cut_mag_phy])
    dmcut = max(0, dmcut)
    return dmcut
end

-- 增伤
local function calc_dmadd(bctx, caster, target, p_cattrs)
    local cattrs, tattrs = caster.attrs, target.attrs
    local feature, dm_type, magic_physical = caster.feature, caster.dm_type,
        caster.magic_physical
    --[[
        伤害加成系数 =  1+伤害增加 + 英雄能力类型伤害加成 +英雄伤害类型加成 + 自身物理/法系伤害增加
        + 敌方能力类型受伤增加 + 敌方伤害类型受伤增加 + 敌方受到的物理/法系伤害增加
    ]]
    local add_fn = "dmadd_features_" .. feature
    local add_tn = "dmadd_type_" .. dm_type
    local injured_feature = "injured_features_" .. feature
    local injured_type = "injured_type_" .. dm_type
    local add_mag_phy = "dmadd_mag_phy_" .. magic_physical
    local injured_mag_phy = "injured_mag_phy_" .. magic_physical
    local p_dmadd = p_cattrs and p_cattrs.dmadd or 0
    local dmadd =
        1 + (cattrs.dmadd + p_dmadd) / attrpara.dmadd + cattrs[add_fn] /
            attrpara[add_fn] + cattrs[add_tn] / attrpara[add_tn] +
            cattrs[add_mag_phy] / attrpara[add_mag_phy] +
            tattrs[injured_feature] / attrpara[injured_feature] +
            tattrs[injured_type] / attrpara[injured_type] +
            tattrs[injured_mag_phy] / attrpara[injured_mag_phy]

    --[[
        攻击某一类英雄时，伤害增加（特性，伤害类型，物理/法系）
    ]]
    local t_feature, t_dm_type, t_magic_physical = target.feature,
        target.dm_type, target.magic_physical
    local t_add_fn = "dmadd_2obj_features_" .. t_feature
    local t_add_tn = "dmadd_2obj_type_" .. t_dm_type
    local t_add_mag_phy = "dmadd_2obj_mag_phy_" .. t_magic_physical
    dmadd = dmadd + cattrs[t_add_fn] / attrpara[t_add_fn] + cattrs[t_add_tn] /
                attrpara[t_add_tn] + cattrs[t_add_mag_phy] /
                attrpara[t_add_mag_phy]
    return dmadd
end

local ptype_attr_attack<const> = ptype.attr_attack
local ptype_attr_hurt<const> = ptype.attr_hurt

-- 基础伤害
function _M.calc_damage(bctx, ctx, caster, target, skill_dmadd)
    local cattrs, tattrs = caster.attrs, target.attrs
    local p_cattrs = passive_attr(bctx, ptype_attr_attack, caster, target, ctx)
    local p_tattrs = passive_attr(bctx, ptype_attr_hurt, target, caster, ctx)

    local atk = cattrs.atk + (p_cattrs and p_cattrs.atk or 0)
    local defcut = cattrs.defcut + (p_cattrs and p_cattrs.defcut or 0)
    local def = tattrs.def + (p_tattrs and p_tattrs.def or 0)
    def = max(1, floor(def * (1 - defcut / attrpara.defcut)))
    --  防御减伤 = 1/（系数1+攻击/（系数2*敌方防御））
    local def_dr = 1 / (CFG.def_dmcut1 + atk / (CFG.def_dmcut2 * def))
    local iscrit, critdm = get_critdm(bctx, caster, target, p_cattrs, p_tattrs)
    local dmadd = calc_dmadd(bctx, caster, target, p_cattrs)
    local dmcut = calc_dmcut(bctx, caster, target, p_tattrs)
    -- 伤害 = 攻击 * 技能效果系数*（1-防御减伤）*（1+暴击伤害加成）* 伤害加成系数 * 伤害减免系数
    local damage = atk * skill_dmadd * (1 - def_dr) * (1 + critdm) * dmadd *
                       dmcut
    -- 分身增伤
    damage = damage * (1 + tattrs.clone_hurtup / attrpara.clone_hurtup)

    -- 等级系数
    local level_diff = caster.ave_level - target.ave_level
    local cfg = LEVEL_DIFF_CFG[abs(level_diff)] or
                    LEVEL_DIFF_CFG[#LEVEL_DIFF_CFG]
    local level_coe = 0
    if level_diff > 0 then
        level_coe = cfg.positive
    else
        level_coe = cfg.negative
    end
    damage = damage * (1 + level_coe / 1000)
    --[[
    log(bctx, caster,
        "%s attack %s damage=%.1f : iscrit=%s,atk=%d,def=%d,def_dr=%.1f,critdm=%.1f,\
        dmadd=%.1f,dmcut=%.1f,skill_dmadd=%.1f,passive_caster=%s,passive_target=%s",
        caster.id, target.id, damage, tostring(iscrit), atk, def, def_dr,
        critdm, dmadd, dmcut, skill_dmadd, p_cattrs and 1 or 0,
        p_tattrs and 1 or 0)
    -- ]]
    assert(not isnan(damage), damage)
    return floor(damage), iscrit
end

-- 溅射伤害减免
function _M.damage_cut(bctx, ctx, damage, caster, target)
    local p_tattrs = passive_attr(bctx, ptype.attr_hurt, target, caster, ctx)
    local dmcut = calc_dmcut(bctx, caster, target, p_tattrs)
    return floor(damage * dmcut)
end

function _M.calc_two_stage_damage(src, damage)
    local two_stage_hurtup = src.attrs.two_stage_hurtup
    if two_stage_hurtup > 0 then
        return floor(damage * two_stage_hurtup / 1000)
    end
end

-- 回血
function _M.calc_hp_by_atk(caster, target, coe, p_attrs)
    local cattrs = caster.attrs
    local atk = cattrs.atk
    local hp = max(0, atk * coe / 1000)
    local cure_p = cattrs.cure_p + (p_attrs and p_attrs.cure_p or 0)
    hp = floor(hp * (1 + cure_p / attrpara.cure_p))
    return max(0, hp)
end

function _M.calc_hp_fixed(self, hp, p_attrs)
    local cattrs = self.attrs
    local cure_p = cattrs.cure_p + (p_attrs and p_attrs.cure_p or 0)
    hp = floor(hp * (1 + cure_p / attrpara.cure_p))
    return max(0, hp)
end

function _M.calc_hp_percent(caster, target, coe)
    local hpmax = target.attrs.hpmax
    local hp = max(0, floor(hpmax * coe / 1000))
    hp = floor(hp)
    return hp
end

function _M.calc_hp_p_lost(self, coe)
    local attrs = self.attrs
    local losthp = attrs.hpmax - attrs.hp
    return max(0, floor(losthp * coe / 1000))
end

function _M.get_killtpv(self)
    local cattrs = self.attrs
    local tpv = max(0, CFG.kill_tpv *
        (1 + cattrs.kill_tpv_up / attrpara.kill_tpv_up))
    return floor(tpv)
end

function _M.calc_tpv_by_atk(self, parm, iscrit)
    local cattrs = self.attrs
    local tpv = parm * (1 + cattrs.tpv_inc / attrpara.tpv_inc)
    local coe = iscrit and CFG.crit_tpv or 1
    tpv = floor(max(0, tpv * coe))
    return tpv
end

function _M.calc_tpv_by_damage(self, damage)
    local cattrs = self.attrs
    local hpmax = cattrs.hpmax
    local tpvmax = cattrs.tpvmax
    local tpv = damage / hpmax * tpvmax * CFG.injured_tpv
    local tpv_inc = cattrs.tpv_inc
    tpv = floor(tpv * (1 + tpv_inc / attrpara.tpv_inc))
    tpv = max(0, tpv)
    return tpv
end

function _M.calc_shield_by_atk(self, coe)
    local cattrs = self.attrs
    local atk = cattrs.atk
    local shield = max(0, atk * coe)
    return floor(shield)
end

function _M.calc_shield_by_hpmax(self, coe)
    local cattrs = self.attrs
    local hpmax = cattrs.hpmax
    local shield = max(0, hpmax * coe)
    return floor(shield)
end

function _M.exchange_skill(bctx, self, skillid)
    local cattrs = self.attrs
    local p = cattrs["exchange_" .. skillid]
    return b_util_random(bctx) <= p
end

function _M.calc_rebound_damage(self, tp, damage)
    local v = 0
    if damage > 0 then
        local cattrs = self.attrs
        local rebound = "rebound_" .. tp
        v = min(damage, floor(damage * max(cattrs[rebound], cattrs.rebound_3) /
                                  attrpara[rebound]))
    end
    return v
end
return _M
