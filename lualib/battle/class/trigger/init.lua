local skynet = require "skynet"
local cfgdata = require "cfg.data"
local objtype = require "battle.objtype"
local fsm = require "battle.fsm"
local mods = require "battle.mods"
local b_util = require "battle.util"
local stat = require "battle.stat"
local attrcalc = require "skillsys.attrcalc"
local class = require "battle.class"("trigger")

local fsm_update = fsm.update

local CFG
skynet.init(function()
    CFG = cfgdata.skill_trigger
end)

local function create(bctx, cfgid, x, y, owner, target)
    local cfg = assert(CFG[cfgid])
    local id = b_util.genid(bctx)
    local self = {
        id = id,
        x = x,
        y = y,
        cfgid = cfgid,
        objtype = objtype.trigger,
        camp = owner.camp,
        owner = owner,
        target = {x = target and target.x, y = target and target.y},
        cfg = cfg,
        start_ti = bctx.btime.now,
        battle_ctx = bctx,
        ave_level = owner.ave_level
    }
    b_util.inherit_tag(self, owner)
    attrcalc.copy(self, owner)
    return self
end

function class.init(bctx, cfgid, x, y, owner, target)
    local self = create(bctx, cfgid, x, y, owner, target)
    class:new(self)
    mods.init(self, bctx)
    stat.push(bctx, owner, "trigger_add", {
        id = self.id,
        cfgid = cfgid,
        x = x,
        y = y,
        targetx = target and target.x,
        targety = target and target.y
    })
    return self
end

function class.destroy(self, bctx)
    mods.destroy(self, bctx)
    self.__valid__ = false
end

function class.update(self, bctx)
    fsm_update(bctx, self)
end

return class
