local skynet = require "skynet"
local fsm = require "battle.fsm"
local fsm_event = require "battle.fsm.event"
local skillsys = require "skillsys"
local object_move = require "battle.move"
local status = require "battle.status"
local status_type = require "battle.status_type"
local buffsys = require "skillsys.buffsys"
local b_util = require "battle.util"
local is_baseskill = skillsys.is_baseskill
local is_activeskill = skillsys.is_activeskill
local is_comboskill = skillsys.is_comboskill
local stat = require "battle.stat"
local clone

skynet.init(function()
    clone = require "battle.clone"
end)

local _M = {}

function _M.on_castover(self, bctx)
    self:clear_skill_target()
    self.next_up_ti = nil
    fsm.transition(bctx, self, fsm_event.cast_over)
end

function _M.on_stopmove(self, bctx, rand_cfg)
    fsm.transition(bctx, self, fsm_event.stop_move)
    if status.check(self, status_type.rand_move) then
        self:on_randmove(bctx, rand_cfg)
    end
end

function _M.on_dead(self, bctx, ctx)
    skillsys.break_cast(bctx, self)
    if self.masterid then
        local o = bctx.objmgr.get(self.masterid)
        if o then clone.remove(o, self.id) end
    end
    clone.sacrifice(bctx, self, ctx)
    fsm.transition(bctx, self, fsm_event.die)
end

function _M.on_addstatus(self, bctx, bindstate)
    for _, s in pairs(bindstate) do
        if s == status_type.no_move then
            object_move.stop_move(bctx, self)
        elseif s == status_type.attack_friend or s == status_type.attack_all then
            self:set_target()
        elseif s == status_type.no_skill_1 then
            local skillid = self.selected_skill
            if skillid and is_baseskill(skillid) then
                self:clear_skill_target()
            end
        elseif s == status_type.no_skill_2_3 then
            local skillid = self.selected_skill
            if skillid and (is_activeskill(skillid) or is_comboskill(skillid)) then
                self:clear_skill_target()
            end
        elseif s == status_type.in_dead then
            stat.damage(bctx, self, 0, self, true)
        end
    end
end

function _M.on_delbuff(self, bctx, buff_uuid)
    if buff_uuid then buffsys.del(bctx, self, buff_uuid) end
end

function _M.on_randmove(self, bctx, rand_cfg)
    if not rand_cfg then return end
    local r_min, r_max = rand_cfg[1] / 100, rand_cfg[2] / 100
    local dest = b_util.rand_dest(bctx, self, {x = self.x, y = self.y}, r_min,
        r_max)
    local target = {hex = dest, x = dest.x, y = dest.y}
    local distance = 0.1
    if object_move.start_move(bctx, self, target, distance, dest, nil, rand_cfg) then
        fsm.transition(bctx, self, fsm_event.moveto)
    end
end

return _M

