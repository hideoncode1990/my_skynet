local objtype = require "battle.objtype"
local status = require "battle.status"
local status_type = require "battle.status_type"
local status_check = status.check
local status_checkand = status.check_and
local status_checkor = status.check_or
local passive_type = require "skillsys.passive_type"
local fsmstate = require "battle.fsm.state"
local _BG = require "battle.global"
local b_util = require "battle.util"
local etype = require "skillsys.etype"

local st_attack_friend<const> = status_type.attack_friend
local st_attack_all<const> = status_type.attack_all
local st_god<const> = status_type.god
local st_no_skill_1<const> = status_type.no_skill_1
local st_no_skill_2<const> = status_type.no_skill_2
local st_no_skill_3<const> = status_type.no_skill_3
local st_no_skill_2_3<const> = status_type.n_skill_2_3
local st_no_control<const> = status_type.no_control
local st_no_choose<const> = status_type.no_choose

local _M = {}

local ulog = b_util.log
local function log(bctx, self, ...)
    ulog(bctx, ...)
end

local function is_dead(self)
    return self.FSMstate == fsmstate.dead
end
_M.is_dead = is_dead

local function set_dead(bctx, self, caster, ctx, push, why)
    if is_dead(self) then return end
    _BG.passive_trigger(bctx, passive_type.dead, self, caster, ctx)
    --[[
    log(bctx, self, "%d(%d) hex(%d,%d) dead %s", self.id, self.cfgid,
        self.hex.hx, self.hex.hy, why or "")
    -- ]]
    self:on_dead(bctx, ctx)
    if push then
        table.insert(ctx.out, {
            etype = etype.die,
            skillid = 0,
            dead = true,
            caster = caster.id,
            target = self.id
        })
    end
end
_M.set_dead = set_dead

function _M.check_hero(self)
    return self.masterid == nil
end

local function check_enemy(self, obj)
    if self.id == obj.id then return false end
    -- 攻击友方
    if status_check(self, st_attack_friend) then return self.camp == obj.camp end
    -- 不分敌我
    if status_check(self, st_attack_all) then return self.id ~= obj.id end
    return self.camp ~= obj.camp
end
_M.check_enemy = check_enemy

local function cant_selected(self)
    if self.objtype ~= objtype.hero then return true end
    if is_dead(self) then return true end
    if status_check(self, st_no_choose) then return true end
    return false
end
_M.cant_selected = cant_selected

function _M.select_enemy(bctx, self, obj)
    if cant_selected(obj) then return false end
    if self.force_target then -- 强制攻击
        local o = bctx.objmgr.get(self.force_target)
        if not o or is_dead(o) then
            self.force_target = nil
        else
            return self.force_target == obj.id
        end
    end
    return check_enemy(self, obj)
end

function _M.can_attacked(self)
    if self.objtype ~= objtype.hero then return false end
    if is_dead(self) then return false end
    if status_check(self, st_god) then return false end
    return true
end

function _M.can_attack(self)
    if is_dead(self) then return false end
    if status_checkand(self, st_no_skill_1, st_no_skill_2_3) then
        return false
    end
    return true
end

function _M.cant_controlled(self)
    if status_checkor(self, st_no_control, st_god) then return true end
    return false
end

function _M.can_add_tpv(self)
    if is_dead(self) then return false end
    if self.objtype ~= objtype.hero then return false end
    return true
end

function _M.check_tag(self, tagid, tagv)
    local tag = b_util.get_tag_type(tagid)
    return self[tag] == tagv
end

function _M.check_friend(self, obj)
    return self.camp == obj.camp
end

function _M.dec_hp(bctx, self, hp, caster, ctx)
    local attrs = self.attrs
    if hp == 0 then return attrs.hp end
    if is_dead(self) then return attrs.hp, true end
    local prior_hp = attrs.hp
    local last = attrs.hp - hp
    if last < 0 then last = 0 end
    attrs.hp = last
    _BG.passive_trigger_Bi(bctx, passive_type.hp_change,
        passive_type.t_hp_change, self, caster, ctx, {prior_hp = prior_hp})
    if last == 0 then
        _BG.passive_trigger(bctx, passive_type.near_dead, self, caster, ctx,
            {prior_hp = prior_hp})
    end
    -- 不死被动效果会修改血量
    last = attrs.hp
    --[[
    log(bctx, self, "dec_hp %s  (%d,%d/%d)", self.id, hp, attrs.hp,
        attrs.hpmax)
    -- ]]
    if last == 0 then
        set_dead(bctx, self, caster, ctx, false, "dec_hp")
        return last, true
    else
        return last
    end
end

function _M.add_hp(bctx, self, hp, caster, ctx)
    local attrs = self.attrs
    local hpmax = attrs.hpmax
    if is_dead(self) then return attrs.hp end
    local prior_hp = attrs.hp
    local last = attrs.hp + hp
    local overhp
    if last > hpmax then
        overhp = last - hpmax
        last = hpmax
    end
    attrs.hp = last
    _BG.passive_trigger_Bi(bctx, passive_type.hp_change,
        passive_type.t_hp_change, self, caster, ctx, {prior_hp = prior_hp})
    last = attrs.hp
    -- log(bctx, self, "add_hp %s (%d,%d/%d)", self.id, hp, last, hpmax)
    return last, overhp
end

function _M.dec_tpv(self, tpv)
    local attrs = self.attrs
    if is_dead(self) then return attrs.tpv, true end
    local last = attrs.tpv - tpv
    if last < 0 then last = 0 end
    attrs.tpv = last
    -- log(bctx, self, "dec_tpv %s (%d,%d/%d)", self.id, tpv, attrs.tpv, attrs.tpvmax)
    return last
end

function _M.add_tpv(self, tpv)
    local attrs = self.attrs
    if is_dead(self) then return attrs.tpv end
    local tpvmax = attrs.tpvmax
    local last = attrs.tpv + tpv
    if last > tpvmax then last = tpvmax end
    attrs.tpv = last
    -- log(bctx, self, "add_tpv %s %d %d/%d", self.id, tpv, last, tpvmax)
    return last
end

function _M.dec_shield(bctx, self, shield, _type)
    local shields = self.shields
    if not shields then return 0, 0, shield end
    local attrs = self.attrs
    local dels = {}
    local left = shield
    for _, v in ipairs(shields) do
        if v[3] & _type ~= 0 then
            if left >= v[2] then
                dels[v[1]] = true
                left = left - v[2]
                v[2] = 0
            else
                v[2] = v[2] - left
                left = 0
                break
            end
        end
    end
    local val = shield - left
    local last = attrs.shield - val
    attrs.shield = last
    for uuid in pairs(dels) do self:on_delbuff(bctx, uuid) end -- effect会调用remove_shield
    -- log(bctx, self, "%s dec_shield %d(%d) %d", self.id, shield, left, last)
    return last, val, left
end

function _M.add_shield(bctx, self, uuid, shield, _type)
    local shields = self.shields
    local attrs = self.attrs
    if not shields then
        shields = {}
        self.shields = shields
    end
    table.insert(shields, {uuid, shield, _type})
    local last = attrs.shield + shield
    attrs.shield = last
    -- log(bctx, self, "%s add_shield %d %d", self.id, shield, last)
    return shield, last
end

function _M.remove_shield(bctx, self, uuid)
    local shields = self.shields
    local attrs = self.attrs
    local last = attrs.shield
    local val = 0
    if not shields then return val, last end
    for i, v in ipairs(shields) do
        if uuid == v[1] then
            val = v[2]
            last = attrs.shield - val
            table.remove(shields, i)
            -- log(bctx, self, "%s remove_shield %d %d", self.id, val, last)
            break
        end
    end
    if not next(shields) then self.shields = nil end
    attrs.shield = last
    return 0 - val, last
end

return _M
