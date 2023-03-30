local _BG = require "battle.global"
local ptype = require "skillsys.passive_type"
local objtype = require "battle.objtype"
local mods = require "battle.mods"
local class = require "battle.class"("commander")

local function create(bctx, camp, o, passive_list)
    local self = o
    self.id = camp
    self.objtype = objtype.trigger
    self.camp = camp
    self.battle_ctx = bctx
    self.objtype = objtype.commander
    self.combo_skill = nil
    self.skilllist = nil
    self.passive_list = passive_list
    return self
end

function class.init(bctx, camp, o, passive_list, ave_level)
    local self = create(bctx, camp, o, passive_list)
    self.ave_level = ave_level
    class:new(self)
    mods.init(self, bctx)
    return self
end

function class.destroy(self, bctx)
    mods.destroy(self, bctx)
end

function class.update(self, bctx)
    if not self.passive_init then
        self.passive_init = true
        _BG.passive_trigger_Bi(bctx, ptype.friend_hero_change,
            ptype.enemy_hero_change, self, self)
        _BG.passive_trigger(bctx, ptype.global_init, self)
    end
end

return class

