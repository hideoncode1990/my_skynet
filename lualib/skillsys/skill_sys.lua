local skynet = require "skynet"
local etype = require "skillsys.etype"
local calc = require "skillsys.calc"
local object_find = require "battle.object_find"
local cfgdata = require "cfg.data"
local stat = require "battle.stat"
local skill_enum = require "skillsys.skill_enum"
local camp_type = require "battle.camp_type"
local status = require "battle.status"
local status_type = require "battle.status_type"
local passive_type = require "skillsys.passive_type"
local _BG = require "battle.global"
local vector2 = require "battle.vector2"
local b_util = require "battle.util"
local profile_add = require"battle.profile".add
local object = require "battle.object"

local ulog = b_util.log
local function log(bctx, self, ...)
    ulog(bctx, ...)
end

local skill_base<const> = 1
local skill_active<const> = 2
local skill_combo<const> = 3
local skill_passive<const> = 4

local SKILL_CFG
local EFFECT_CFG

local stat_push = stat.push

local sqrt = math.sqrt
local floor = math.floor
local max = math.max
local abs = math.abs
local ceil = math.ceil
local min = math.min

local type = type
local next = next

local ipairs = ipairs
local insert = table.insert
local remove = table.remove
local assert = assert

local vector2_distance = vector2.distance

local b_util_random = b_util.random

local passive_trigger = _BG.passive_trigger
-- local use_combo = _BG.use_combo
local passive_load = _BG.passive_load
local passive_unload = _BG.passive_unload
local passive_check = _BG.passive_check

local exchange_skill = calc.exchange_skill
local get_hit_opps = calc.get_hit_opps

local find_target_strategy = object_find.find_target_strategy

local skill_enum_out_of_range<const> = skill_enum.out_of_range
local skill_enum_succ<const> = skill_enum.succ
local skill_enum_no_skill<const> = skill_enum.no_skill
local skill_enum_skill_forbid<const> = skill_enum.skill_forbid
local skill_enum_skill_incd<const> = skill_enum.skill_incd
local skill_enum_tpv_not_enough<const> = skill_enum.tpv_not_enough
local skill_enum_cant_attack<const> = skill_enum.cant_attack
local status_check = status.check

local ptype_startcast<const> = passive_type.start_cast
local ptype_becaststart<const> = passive_type.be_cast_start
local ptype_castover<const> = passive_type.cast_over

local _M = {}

skynet.init(function()
    SKILL_CFG = cfgdata.skill
    EFFECT_CFG = cfgdata.effect
end)

local function range_offset(src, skillid, tobj)
    local scfg = SKILL_CFG[skillid]
    local range
    if tobj.body or src.body then
        range = scfg.range + sqrt(3)
    else
        range = scfg.range
    end
    return range
end

_M.range_offset = range_offset

local function check_distance(bctx, src, skillid, tobj)
    local range = range_offset(src, skillid, tobj)
    local lv, rv
    if tobj then
        lv = vector2_distance(src, tobj)
        rv = range
        -- lv = (tobj.x - src.x) ^ 2 + (tobj.y - src.y) ^ 2
        -- rv = (range + 0.01) ^ 2
    end
    --[[
    log(bctx, src,
        "%s check_distance [%d] [%f,%f] (%f,%f)[%d,%d]-(%f,%f)[%d,%d]", src.id,
        skillid, lv, rv, src.x, src.y, src.hx or 0, src.hy or 0, tobj.x, tobj.y,
        tobj.hx or 0, tobj.hy or 0)
    -- ]]
    if lv > rv then return skill_enum_out_of_range, range end
    return skill_enum_succ
end

local function check_cast_other(bctx, src, skillid, tobj)
    if src.skills and not src.skills[skillid] then return skill_enum_no_skill end

    local scfg = SKILL_CFG[skillid]
    local status_name = "no_skill_" .. scfg.skilltype
    if status_check(src, status_type[status_name]) then
        return skill_enum_skill_forbid
    end

    local nextcast = src.skillsys_skillcd[skillid] or 0
    if bctx.btime.now < nextcast then return skill_enum_skill_incd end
    return skill_enum_succ
end
_M.check_cast_other = check_cast_other

local function check_cost(bctx, src, skillid)
    local scfg = SKILL_CFG[skillid]
    local tpv = scfg.cost
    if tpv and tpv > 0 then
        if tpv > src.attrs.tpv then return skill_enum_tpv_not_enough end
    end
    return skill_enum_succ
end

local checkcast_call = {check_distance, check_cast_other, check_cost}
local function check_cast(bctx, src, ctx, tobj)
    if not object.can_attack(src) then return skill_enum_cant_attack end
    local e, m
    for _, call in ipairs(checkcast_call) do
        e, m = call(bctx, src, ctx, tobj)
        if e ~= skill_enum_succ then break end
    end
    if e ~= skill_enum_succ then return e, m end
    return skill_enum_succ
end

_M.check_cast = check_cast

local function calc_realcast_target(self, tobj, scfg)
    local folltype = scfg.folltype
    local x, y, objid
    if folltype == 1 then
        x, y, objid = nil, nil, tobj.id
    elseif folltype == 2 then
        x, y, objid = tobj.x, tobj.y, nil
    end
    return x, y, objid
end

local function do_cast(bctx, src, ctx, tobj)
    local scfg = ctx.scfg
    local x, y, objid = calc_realcast_target(src, tobj, scfg)
    ctx.x = x
    ctx.y = y
    ctx.objid = objid
    src.skillsys_incast = ctx
    stat_push(bctx, src, "skill_start_cast", {
        caster = src.id,
        skillid = ctx.skillid,
        target = tobj.id,
        targetx = tobj.x,
        targety = tobj.y,
        casterx = src.x,
        castery = src.y,
        ti = ctx.ti,
        timestop = ctx.timestop,
        skip = bctx.skip
    })
    passive_trigger(bctx, ptype_startcast, src, tobj, ctx)
    if tobj then passive_trigger(bctx, ptype_becaststart, tobj, src, ctx) end
    return 0
end

function _M.cast_start(bctx, self, skillid, tobj)
    local scfg = SKILL_CFG[skillid]
    if not scfg then error("not find skill setting " .. tostring(skillid)) end

    local e = check_cast(bctx, self, skillid, tobj)
    if e ~= 0 then return e end
    local now = bctx.btime.now
    local atkspeed = self.attrs.atkspeed
    local cd = floor(max(0, scfg.cd / atkspeed))
    self.skillsys_skillcd[skillid] = now + cd +
                                         (self.skillsys_CDs[skillid] or 0)

    if scfg.exchange and exchange_skill(bctx, self, skillid) then
        skillid = scfg.exchange
        scfg = assert(SKILL_CFG[skillid])
    end
    --[[
    log(bctx, self, "cast_skill %s(%d,%d) [%d] %s(%d,%d)", self.id, self.hex.hx,
        self.hex.hy, skillid, tostring(tobj.id), tostring(tobj.hex.hx),
        tostring(tobj.hex.hy))
    -- ]]
    local ctx = {
        caster = self.id,
        skillid = skillid,
        scfg = scfg,
        ti = now,
        seq_no = 1,
        atkspeed = atkspeed
    }
    if self:can_timestop(bctx, skillid) then
        ctx.timestop = true
        _BG.pause(bctx, true)
    end
    do_cast(bctx, self, ctx, tobj)
    if scfg.skilltype == skill_combo then _BG.use_combo(bctx, self, tobj) end
    return 0
end

local find = {}
function _M.register_findtarget(type, call)
    find[type] = call
end

local function calc_effect_target(bctx, ecfg, src, tobj, x, y, ctx)
    local call = find[ecfg.findtarget]
    return call(bctx, ecfg, src, tobj, x, y, ctx)
end
_M.calc_effect_target = calc_effect_target

local erun = {}
function _M.register_effect(type, call)
    erun[type] = call
end

local function cast_effect(bctx, self, ctx, _id, target, x, y, e_args, ...)
    local negative_effect
    local id = _id
    if id < 0 then
        id = abs(id)
        negative_effect = true
    end
    local ecfg = EFFECT_CFG[id]
    if not ecfg then error("not find effect setting " .. tostring(id)) end
    local effectcd = self.skillsys_effectcd
    local now = bctx.btime.now
    local cfgcd = ecfg.cd
    if cfgcd and not negative_effect then
        if now < (effectcd[id] or 0) then return end
        effectcd[id] = cfgcd + now
    end
    local targets = calc_effect_target(bctx, ecfg, self, target, x, y, ctx)
    local hit_targets = {}
    for _, tobj in ipairs(targets) do
        if not object.is_dead(tobj) then
            local hit_opps
            if ecfg.hit == 0 then
                local generic_skill = ctx.scfg.skilltype == skill_base
                hit_opps = get_hit_opps(self, tobj, generic_skill)
            else
                hit_opps = ecfg.hit
            end
            local hit = b_util_random(bctx) / 1000 <= hit_opps
            if hit then
                insert(hit_targets, tobj)
                local call = erun[ecfg.type]
                if not call then
                    error("unknow ecfg type" .. tostring(ecfg.id) .. "_" ..
                              tostring(ecfg.type))
                end
                --[[
                log(bctx, self, "%s cast_effect %d etype %d target %s", self.id,
                    _id, ecfg.type, tobj.id)
                -- ]]
                local deep = bctx.deep
                insert(deep, _id)
                if #deep > 10 then
                    error("effect too deep " .. table.concat(deep, ","))
                end
                call(bctx, self, ctx, tobj, ecfg, e_args, negative_effect, ...)
                local theid = remove(deep)
                assert(theid == _id)
            else
                insert(ctx.out, {
                    effectid = ecfg.id,
                    etype = etype.dodge,
                    skillid = ctx.skillid,
                    caster = self.id,
                    target = tobj.id
                })
            end
        end
    end
    if #hit_targets > 0 then return hit_targets end
end

local function cast_effectlist(bctx, self, ctx, effectcast, tobj, x, y, ...)
    local hit_targets
    local cond_effect = effectcast[0] -- if effect[0] is hit then cast effect[1-n]
    if cond_effect then
        local id = cond_effect
        hit_targets = cast_effect(bctx, self, ctx, id, tobj, x, y, ...)
        ctx.targets = hit_targets
        if not hit_targets then return end
    end
    if cond_effect then
        if hit_targets then
            for _, id in ipairs(effectcast) do
                if type(id) == "number" then
                    for _, _tobj in ipairs(hit_targets) do
                        cast_effect(bctx, self, ctx, id, _tobj, _tobj.x,
                            _tobj.y, ...)
                    end
                else
                    for _, _tobj in ipairs(hit_targets) do
                        cast_effectlist(bctx, self, ctx, id, _tobj, _tobj.x,
                            _tobj.y, ...)
                    end
                end
            end
        end
    else
        for _, id in ipairs(effectcast) do
            if type(id) == "number" then
                cast_effect(bctx, self, ctx, id, tobj, x, y, ...)
            else
                cast_effectlist(bctx, self, ctx, id, tobj, x, y, ...)
            end
        end
    end
end

local function check_toolarge(bctx, self, list)
    local maxcnt = 100
    if #list > maxcnt then
        local tt = {}
        for i = 1, maxcnt do table.insert(tt, list[i].effectid or 0) end
        local s = table.concat(tt, ",")
        bctx.verify = true
        log(bctx, self, "msg toolarge %s", s)
    end
end

local function cast_skill_effectlist(bctx, self, ctx, effectcast, tobj, x, y)
    local out = ctx.out
    if not out then ctx.out = {} end
    cast_effectlist(bctx, self, ctx, effectcast, tobj, x, y)
    if not out then
        local msg = {
            caster = self.id,
            skillid = ctx.skillid or 0,
            target = tobj and tobj.id,
            targetx = x,
            targety = y,
            casterx = self.x,
            castery = self.y,
            list = ctx.out,
            ti = ctx.ti,
            order_ti = ctx.order_ti
        }
        check_toolarge(bctx, self, ctx.out)
        ctx.out = nil
        stat_push(bctx, self, "skill_real_cast", msg)
    end
end

_M.cast_skill_effectlist = cast_skill_effectlist

function _M.cast_effectlist(bctx, self, ctx, effectcast, tobj, x, y, ...)
    ctx.scfg = ctx.scfg or {skillid = 0}
    ctx.target = tobj and tobj.id
    ctx.x = x
    ctx.y = y
    local out = ctx.out
    if not out then ctx.out = {} end
    cast_effectlist(bctx, self, ctx, effectcast, tobj, x, y, ...)
    if not out then
        out, ctx.out = ctx.out, nil
        if next(out) then
            check_toolarge(bctx, self, out)
            stat_push(bctx, self, "skill_effect", {list = out})
        end
    end
end

function _M.find_target(bctx, self, skillid)
    local scfg = SKILL_CFG[skillid]
    if not scfg then error("not find skill setting " .. tostring(skillid)) end
    return find_target_strategy(bctx, self, scfg.target_strategy)
end

local function cast_over(bctx, self, why)
    local ctx = self.skillsys_incast
    if ctx then
        --[[
        log(bctx, self, "%s(%d) cast_over %s", self.id,
            self.skillsys_incast.skillid, why or "")
        -- ]]
        self.skillsys_incast = nil
        self:on_castover(bctx)
        if ctx.timestop then bctx.caster = nil end
    end
end

function _M.check_casting(bctx, self)
    local ctx = self.skillsys_incast
    if ctx and ctx.next_casting then
        local t = bctx.btime.now - ctx.next_casting
        return t >= 0, ceil(0 - t)
    end
    return true
end

function _M.get_nextcast_ti(self)
    local ctx = self.skillsys_incast
    if ctx then return ctx.next_casting end
end

local function timestop_casting(bctx, self, tobj, scfg)
    local ctx = self.skillsys_incast
    local x, y = ctx.x, ctx.y
    for _, sub_skill in ipairs(scfg.order) do
        local ti, effects = sub_skill[1], sub_skill[2]
        ctx.order_ti = ti * 10
        cast_skill_effectlist(bctx, self, ctx, effects, tobj, x, y)
    end
    passive_trigger(bctx, ptype_castover, self, tobj, ctx)
    cast_over(bctx, self, "timeover")
    stat_push(bctx, self, "skill_combo_over", {skillid = ctx.skillid})
    return true
end

local function normal_casting(bctx, self, tobj, scfg)
    local ctx = self.skillsys_incast
    local cast_ti, seq_no, atkspeed = ctx.ti, ctx.seq_no, ctx.atkspeed
    local casttime = scfg.casttime / atkspeed
    local skill_order = scfg.order
    local now = bctx.btime.now
    local sub_order = skill_order[seq_no]
    if sub_order then
        local next_ti = cast_ti + sub_order[1]
        if now >= next_ti then
            seq_no = seq_no + 1
            ctx.seq_no = seq_no
            cast_skill_effectlist(bctx, self, ctx, sub_order[2], tobj, ctx.x,
                ctx.y)
            local next_order = skill_order[seq_no]
            ctx.next_casting = cast_ti +
                                   (next_order and next_order[1] or casttime)
        else
            ctx.next_casting = next_ti
        end
    end
    if now >= cast_ti + casttime then
        passive_trigger(bctx, ptype_castover, self, tobj, ctx)
        cast_over(bctx, self, "timeover")
        return true, true
    end
    return true
end

function _M.casting(bctx, self)
    local ctx = self.skillsys_incast
    local tobj = bctx.objmgr.get(ctx.objid)
    local scfg = ctx.scfg
    if (not tobj or not object.can_attacked(tobj)) and scfg.folltype ~= 2 then
        cast_over(bctx, self, "cant_attacked")
        return true, true
    end
    if ctx.timestop then
        timestop_casting(bctx, self, tobj, scfg)
    else
        normal_casting(bctx, self, tobj, scfg)
    end
end

function _M.break_cast(bctx, self)
    local ctx = self.skillsys_incast
    if ctx then
        cast_over(bctx, self, "break")
        stat_push(bctx, self, "skill_break",
            {id = self.id, skillid = ctx.skillid})
    end
end

function _M.get_scfg(skillid)
    return SKILL_CFG[skillid]
end

function _M.check_skillcd(bctx, self, skillid)
    local nextcast = self.skillsys_skillcd[skillid] or 0
    return bctx.btime.now >= nextcast
end

function _M.check_cost(bctx, self, skillid)
    local e = check_cost(bctx, self, skillid)
    return e == skill_enum.succ
end

function _M.is_baseskill(skillid)
    local cfg = SKILL_CFG[skillid]
    return cfg.skilltype == skill_base
end

function _M.is_activeskill(skillid)
    local cfg = SKILL_CFG[skillid]
    return cfg.skilltype == skill_active
end

function _M.is_comboskill(skillid)
    local cfg = SKILL_CFG[skillid]
    return cfg.skilltype == skill_combo
end

local function add_passive(bctx, self, skilllist)
    for i = #skilllist, 1, -1 do
        local skillid = skilllist[i]
        local scfg = SKILL_CFG[skillid]
        local passive_effect = scfg.passive_effect
        if passive_effect then
            if not scfg.order then
                assert(scfg.skilltype == skill_passive)
            end
            passive_load(bctx, self, passive_effect)
            if scfg.skilltype == skill_passive then
                remove(skilllist, i)
            end
        end
    end
end

local function del_passive(bctx, self, skilllist)
    for i = #skilllist, 1, -1 do
        local skillid = skilllist[i]
        local scfg = SKILL_CFG[skillid]
        if scfg.passive_effect then
            if not scfg.order then
                assert(scfg.skilltype == skill_passive)
            end
            passive_unload(bctx, self, scfg.passive_effect)
        end
    end
end

local function skillindex_cmp(a, b)
    local a_skill, b_skill = SKILL_CFG[a], SKILL_CFG[b]
    return (a_skill.index or 0) > (b_skill.index or 0)
end
function _M.init_skilllist(bctx, self)
    local skills = {}
    local skilllist = self.skilllist
    add_passive(bctx, self, skilllist)
    table.sort(skilllist, skillindex_cmp)

    local skillsys_skillcd = self.skillsys_skillcd
    local now = bctx.btime.now
    for _, id in pairs(skilllist) do
        local cfg = SKILL_CFG[id]
        if cfg.startcd then skillsys_skillcd[id] = now + cfg.startcd end
        skills[id] = skill_enum.normal
    end

    local combo_skill = self.combo_skill
    if combo_skill then
        local combo_state = skill_enum.timestop
        local no_play = bctx.no_play
        local no_timestop
        if self.camp == camp_type.right and bctx.no_timestop then
            no_timestop = true
            combo_state = skill_enum.normal
        end
        local cfg = SKILL_CFG[combo_skill]
        if no_play or no_timestop then
            combo_skill = assert(cfg.noplay_skill)
            cfg = SKILL_CFG[combo_skill]
            self.combo_skill = combo_skill
        end
        if cfg.startcd then
            skillsys_skillcd[combo_skill] = now + cfg.startcd
        end
        skills[combo_skill] = combo_state
        add_passive(bctx, self, {combo_skill})
    end
    self.skills = skills
end

function _M.replace_skill(bctx, self, s_skill, t_skill)
    local ok
    local skills = self.skills
    if s_skill == self.combo_skill then
        self.combo_skill = t_skill
        skills[t_skill], skills[s_skill] = skills[s_skill], nil
        ok = true
    else
        local skilllist = self.skilllist
        for i, skill in ipairs(skilllist) do
            if skill == s_skill then
                skilllist[i] = t_skill
                skills[t_skill], skills[s_skill] = skills[s_skill], nil
                ok = true
                break
            end
        end
    end
    if ok then
        local skillsys_skillcd = self.skillsys_skillcd
        if skillsys_skillcd[s_skill] then
            skillsys_skillcd[t_skill], skillsys_skillcd[s_skill] =
                skillsys_skillcd[s_skill], nil
        end
        del_passive(bctx, self, {s_skill})
        add_passive(bctx, self, {t_skill})
    end
end

function _M.exist_skill(self, skillid)
    local skills = self.skills
    return skills[skillid]
end

function _M.init(self, bctx)
    self.skillsys_skillcd = {}
    self.skillsys_effectcd = {}
    self.skillsys_CDs = {} -- 技能cd延长
    self.skillsys_incast = nil
    if self.skilllist then _M.init_skilllist(bctx, self) end
end

function _M.destroy(self)
    self.skillsys_incast = {}
    self.skillsys_skillcd = {}
    self.skillsys_effectcd = {}
    self.skillsys_CDs = {}
end

require "battle.mods"("skillsys", _M)

return _M
