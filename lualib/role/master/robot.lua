local _MAS = require "handler.master"
local legion_trial = require "role.m_legion_trial"
local skynet = require "skynet"
local _H = require "handler.client"
local battle = require "battle"
local uattrs = require "util.attrs"
local json = require "rapidjson.c"

local function battle_test(self, msg)
    local ctx = msg.ctx
    local bctx<close> = battle.create(ctx.nm, ctx.mapid, ctx)
    assert(battle.join(bctx, self))
    local left, right = msg.left, msg.right
    for _, o in pairs(left) do
        o.baseattrs = uattrs.for_fight(o.baseattrs)
        o.zdl = uattrs.zdl(o.baseattrs)
    end
    for _, o in pairs(right) do
        o.baseattrs = uattrs.for_fight(o.baseattrs)
        o.zdl = uattrs.zdl(o.baseattrs)
    end
    battle.start(bctx, {heroes = msg.left}, {heroes = msg.right},
        function(ok, ret)
            if ctx.verify and not ret.terminate then
                local report = ret.report
                skynet.newservice("test/replay", report.uuid,
                    json.encode(report), self.rid, self.fd)
            end
            battle.push(self, {win = ret.win, terminate = ret.terminate})
        end)
    return {e = 0}
end

function _MAS.robot_battle_test_load(self)
    _H.battle_test = battle_test
end

function _MAS.robot_legion_trial_reset(self)
    legion_trial.robot_legion_trial_reset(self)
end
