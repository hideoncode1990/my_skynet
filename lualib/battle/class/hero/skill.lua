local skillsys = require "skillsys"
local camp_type = require "battle.camp_type"
local skill_enum = require "skillsys.skill_enum"
local check_cost = skillsys.check_cost
local check_cast_other = skillsys.check_cast_other
local _BG = require "battle.global"

local _M = {}

function _M.select_skill(self, bctx)
    if self.selected_skill then return self.selected_skill end
    local auto = bctx.auto
    if auto or self.camp == camp_type.right then
        local skillid = self.combo_skill
        if skillid and check_cast_other(bctx, self, skillid) == skill_enum.succ and
            check_cost(bctx, self, skillid) then
            if auto and self.camp == camp_type.left then
                _BG.record_skill(bctx, self.id, skillid)
            end
            self:set_skill_queue()
            return skillid
        end
    end
    local skill_queue = self.skill_queue
    if skill_queue then
        local skillid = skill_queue[1]
        if check_cast_other(bctx, self, skillid) == skill_enum.succ then
            table.remove(skill_queue, 1)
            if not skill_queue[1] then self:set_skill_queue() end
            return skillid
        end
    end
    local skilllist = self.skilllist
    local len = #skilllist
    local order = self.skill_order % len + 1
    for _ = 1, len do
        local skillid = skilllist[order]
        if check_cast_other(bctx, self, skillid) == skill_enum.succ then
            self.skill_order = order
            return skillid
        end
        order = order + 1
        if order > len then order = order % len end
    end
end

function _M.use_skill(self, bctx, skillid)
    if skillid ~= self.combo_skill then return false, 8 end
    if self.selected_skill == self.combo_skill then return false, 5 end
    if check_cast_other(bctx, self, skillid) ~= skill_enum.succ then
        return false, 9
    end
    skillsys.break_cast(bctx, self)
    self:set_skill(skillid)
    self:set_skill_queue()
    return true, 0
end

function _M.set_skill_queue(self, ids)
    self.skill_queue = ids
    if ids then
        for _, id in ipairs(ids) do self.skills[id] = skill_enum.normal end
    end
    return ids
end

function _M.set_skill(self, skillid)
    self.selected_skill = skillid
    return skillid
end

function _M.set_target(self, tobj)
    local id = tobj and tobj.id
    self.targetid = id
    return tobj
end

function _M.clear_skill_target(self)
    self.selected_skill = nil
    self.targetid = nil
end

function _M.can_timestop(self, bctx, skillid)
    if bctx.nostop_all then return false end
    if skillid ~= self.combo_skill then return false end
    if self.skills[skillid] ~= skill_enum.timestop then return false end
    return true
end

return _M
