local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local _MAS = require "handler.master"
local battle = require "battle"
local uattrs = require "util.attrs"
local heroattrs = require "hero.attrs"
local hero = require "hero"
local m_battle = require "role.m_battle"
local timer = require "timer"

local BASIC

skynet.init(function()
    BASIC = cfgproxy("basic")
end)

local inwait, timeout
local function initial_battle(self, id, last_result)
    local cfg = BASIC["initial_battle" .. id]
    local left = m_battle.create_monsters(cfg[1])
    local right = m_battle.create_monsters(cfg[2])

    if last_result then
        local l_ret = last_result.left
        for _, o in ipairs(left.heroes) do o.lasthp = l_ret[o.cfgid] end

        local r_ret = last_result.right
        for _, o in ipairs(right.heroes) do o.lasthp = r_ret[o.cfgid] end
    end

    local auto = BASIC.initial_battle_auto == 1
    local ctx<close> = battle.create("battle_gm", BASIC.initial_battle_map,
        {auto = auto})
    if not battle.join(ctx, self) then return false end
    battle.start(ctx, left, right, function(_ok, ret)
        if not _ok then
            battle.abnormal_push(self)
        else
            battle.push(self, ret)
        end
        if inwait then
            local result = {left = {}, right = {}}
            for _, o in pairs(ret.report.left.heroes) do
                local lo = ret.left[o.id]
                if lo then result.left[o.cfgid] = lo.hp end
            end
            for _, o in pairs(ret.report.right.heroes) do
                local ro = ret.right[o.id]
                if ro then result.right[o.cfgid] = ro.hp end
            end
            inwait.ret = result
            skynet.wakeup(inwait)
        end
    end)
    return true, left, right
end

local function battle_gm(self)
    if not initial_battle(self, 1) then
        inwait = nil
        return
    end
    local wid = timer.add(20000, function()
        timeout = true
        skynet.wakeup(inwait)
    end)
    skynet.wait(inwait)
    timer.del(wid)
    local ret
    ret, inwait = inwait.ret, nil
    if timeout then return end
    initial_battle(self, 2, ret)
end

function _MAS.battle_gm(self)
    assert(not inwait)
    inwait = {}
    skynet.fork(battle_gm, self)
    return {e = 0}
end

-----------------------------------------------------------------------
local fixed = {}
heroattrs.reg("master_battle", function()
    return fixed
end)

function _MAS.battle_attr(self, ctx)
    local key, val = ctx.query.key, ctx.query.val
    fixed[assert(math.tointeger(key))] = assert(math.tointeger(val))
    hero.foreach(self, function(_, uuid)
        heroattrs.dirty(self, "master_battle", uuid)
    end)
    return {e = 0}
end

local replay = require "replay"
function _MAS.battle_replay_expire(self, ctx)
    local expire_time = (ctx.query.expire_time or 0) * 24 * 3600
    replay.check_and_del_expire(expire_time)
    return {e = 0}
end

function _MAS.battle_replay(self, ctx)
    local uuid = ctx.query.uuid
    local skip = ctx.query.skip
    local player = {rid = self.rid, fd = self.fd, addr = self.addr}
    local ok, ret = replay.play(uuid, player)
    assert(ok, ret)
    return {e = 0}
end
