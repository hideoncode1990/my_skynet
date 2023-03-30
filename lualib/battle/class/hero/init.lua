local objtype = require "battle.objtype"
local fsm_state = require "battle.fsm.state"
local _BG = require "battle.global"
local ptype = require "skillsys.passive_type"
local buffsys = require "skillsys.buffsys"
local fsm = require "battle.fsm"
local b_util = require "battle.util"
local stat = require "battle.stat"
local mods = require "battle.mods"
local class = require "battle.class"("hero")
local log = b_util.log
local mathmin = math.min
local passive_trigger = _BG.passive_trigger
local fsm_update = fsm.update
local buffsys_update = buffsys.update
local ptype_init<const> = ptype.init
local skill_sys = require "skillsys"
local get_nextcast_ti = skill_sys.get_nextcast_ti
local get_nextbuff_ti = buffsys.get_nextbuff_ti
local passive_type = require "skillsys.passive_type"

function class.init(bctx, self, camp, pos_idx, ave_level)
    self.camp = camp
    self.pos_idx = pos_idx
    self.objtype = objtype.hero
    self.ave_level = ave_level
    self.battle_ctx = bctx
    self.skill_order = 0
    self.report = {
        id = self.id,
        cfgid = self.cfgid,
        level = self.level,
        pos = self.pos,
        damage = 0,
        hurt = 0,
        heal = 0,
        kill = 0
    }

    class:new(self)
    if self.wood then self.FSMstate = fsm_state.wood end
    bctx.objmgr.add(bctx, self)
    mods.init(self, bctx)
    stat.push(bctx, self, "battle_hero", self)

    return self
end

function class.destroy(self, bctx)
    mods.destroy(self, bctx)
    bctx.objmgr.remove(bctx, self.id)
    self.__valid__ = false
    _BG.hero_dead(bctx, self)
end

local function life_update(bctx, self)
    local attrs = self.attrs
    local prior_frame_hp = self.prior_frame_hp or attrs.hpmax
    local hp = attrs.hp
    if prior_frame_hp ~= hp then
        self.prior_frame_hp = hp
        _BG.passive_trigger(bctx, passive_type.hpchg_next_frame, self, self, {},
            {prior_hp = prior_frame_hp})
    end
end

function class.update(self, bctx, preskill)
    if not self.passive_first then
        self.passive_first = true
        passive_trigger(bctx, ptype_init, self)
    end
    -- 清除buff时，会清除沉默状态,replay先调用use_skill会导致释放技能失败
    buffsys_update(bctx, self)
    if preskill then
        if not self:use_skill(bctx, preskill) then
            log(bctx, "traceback hero %s auto_setskill %d error", self.id,
                preskill)
        end
    end
    fsm_update(bctx, self)
    life_update(bctx, self)

    -- 只有在释放技能期间，才需要和buff时间比较，确定下次update
    local nextcast_ti = get_nextcast_ti(self)
    if nextcast_ti then
        local nextbuff_ti = get_nextbuff_ti(self)
        self.next_up_ti = mathmin(nextcast_ti, nextbuff_ti or nextcast_ti)
    end
end

return class
