local fsm = require "battle.fsm"
local fsm_event = require "battle.fsm.event"
local skillsys = require "skillsys"
local stat = require "battle.stat"
local b_util = require "battle.util"
local _M = {}

function _M.fsm_idle(self, bctx)
    local up_ti = self.up_ti or self.start_ti
    local cfg = self.cfg
    local interval = cfg.interval
    if bctx.btime.now < up_ti + interval then return end
    local target = self.target
    local x = target and target.x
    local y = target and target.y
    skillsys.cast_effectlist(bctx, self, {}, cfg.effects, nil, x, y)
    up_ti = up_ti + interval
    if cfg.duration > 0 and up_ti >= self.start_ti + cfg.duration then
        stat.push(bctx, self, "trigger_del", {id = self.id})
        fsm.transition(bctx, self, fsm_event.die)
    end
    self.up_ti = up_ti
end

function _M.fsm_dead(self, bctx)
    self:destroy(bctx)
end

return _M

