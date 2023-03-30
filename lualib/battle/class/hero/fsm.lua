local fsm = require "battle.fsm"
local fsm_event = require "battle.fsm.event"
local skillsys = require "skillsys"
local object_move = require "battle.move"
local skill_enum = require "skillsys.skill_enum"
local object = require "battle.object"
local _M = {}

local find_target = skillsys.find_target
local check_cast = skillsys.check_cast
local check_casting = skillsys.check_casting
local casting = skillsys.casting
local cast_start = skillsys.cast_start
local range_offset = skillsys.range_offset
local object_need_move = object_move.need_move
local object_start_move = object_move.start_move
local object_move_update = object_move.move_update
local fsm_transition = fsm.transition
local object = require "battle.object"

local skill_enum_out_of_range<const> = skill_enum.out_of_range
local skill_enum_succ<const> = skill_enum.succ

local fsm_event_cast<const> = fsm_event.cast

function _M.fsm_idle(self, bctx)
    local skillid = self.selected_skill or
                        self:set_skill(self:select_skill(bctx))
    if not skillid then return end
    local target = bctx.objmgr.get(self.targetid)
    if target and object.is_dead(target) then target = self:set_target() end
    if not target then
        local ok, obj = find_target(bctx, self, skillid)
        if ok then
            target = obj
            self:set_target(obj)
        end
    end
    if target then
        local e, m = check_cast(bctx, self, skillid, target)
        if e == skill_enum_succ and object_need_move(self) then
            e = skill_enum_out_of_range
            m = range_offset(self, skillid, target)
        end
        if e == skill_enum.succ then
            fsm_transition(bctx, self, fsm_event_cast)
        elseif e == skill_enum_out_of_range then
            if object_start_move(bctx, self, target, m) then
                fsm_transition(bctx, self, fsm_event.moveto)
                -- else
                -- self:set_target()
            end
        end
    end
end

function _M.fsm_move(self, bctx)
    object_move_update(bctx, self)
end

local function cast(bctx, self)
    if check_casting(bctx, self) then casting(bctx, self) end
end

function _M.fsm_cast(self, bctx)
    if check_casting(bctx, self) then casting(bctx, self) end
end

function _M.fsm_dead(self, bctx)
    self:destroy(bctx)
end

function _M.fsm_enter_cast(self, bctx)
    local target = bctx.objmgr.get(self.targetid)
    if target and object.can_attacked(target) then
        local skillid = self.selected_skill
        local e = cast_start(bctx, self, skillid, target)
        if e == 0 then return casting(bctx, self) end
    end
    fsm_transition(bctx, self, fsm_event.cast_failure)
end

return _M

