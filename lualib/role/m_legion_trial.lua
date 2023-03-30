local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local utime = require "util.time"
local fnopen = require "role.fnopen"
local _H = require "handler.client"
local _LUA = require "handler.lua"
local cache = require "mongo.role"("legion_trial")
local variable = require "variable"
local client = require "client"
local m_battle = require "role.m_battle"
local battle = require "battle"
local wintype = require "battle.win_type"
local award = require "role.award"
local flowlog = require "flowlog"
local uaward = require "util.award"
local addition = require "role.addition"
local awardtype = require "role.award.type"
local task = require "task"
local herobest = require "hero.best"
local hinit = require "hero"
local LOCK = require "skynet.queue"()
local NM<const> = "legion_trial"

local _M = {}

local BASIC
local legion_trialmgr, legiond
skynet.init(function()
    BASIC = cfgproxy("basic")
    legion_trialmgr = skynet.uniqueservice("game/legion_trialmgr")
end)

require("role.mods") {
    name = NM,
    enter = function(self)
        skynet.send(legion_trialmgr, "lua", "reenter", self.rid, self.fd)
    end,
    leave = function(self)
        skynet.send(legion_trialmgr, "lua", "leave", self.rid)
    end
}

local function check_reset(self)
    local C = cache.get(self)
    if (C.ver and C.ver ~= BASIC.legion_ver) then return true end
    if (C.endti and C.endti <= utime.time()) then return true end
end

local function calc_time(self)
    local startti = utime.begin_day(variable["starttime_" .. self.sid])
    local now = utime.time()
    local diff = now - startti
    local duration = BASIC.legion_trial_first
    if diff < duration then
        return startti + (diff // duration + 1) * duration
    end

    startti = startti + duration
    diff = now - startti
    duration = BASIC.legion_trial_duration
    local index = diff // duration
    return startti + (index + 1) * duration
end

local function start(self)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local C = cache.get(self)
    local reset = check_reset(self)
    local role = {
        rid = self.rid,
        rname = self.rname,
        level = self.level,
        fd = self.fd,
        addr = skynet.self(),
        mainline = self.mainline,
        ave_stage = hinit.stage_top5_average(self)
    }
    local ret = skynet.call(legion_trialmgr, "lua", "enter", role, reset)
    if ret.new then
        C.endti = calc_time(self)
        C.ver = ret.ver
        C.round = (C.round or 0) + 1
        task.trigger(self, "legion")
        cache.dirty(self)
    end
    legiond = ret.addr
    flowlog.role(self, NM, {
        round = C.round,
        opt = "enter",
        sceneid = ret.sceneid,
        current = ret.current
    })
    return {e = 0, endti = C.endti}
end

function _H.legion_trial_start(self, msg)
    return LOCK(start, self)
end

function _H.legion_trial_select(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    if check_reset(self) then return {e = 19} end
    if not legiond then return {e = 2} end
    local e, ret = skynet.call(legiond, "lua", "select", self.rid, msg.pos,
        msg.index)
    if e == 0 then
        local C = cache.get(self)
        flowlog.role(self, NM, {
            pos = msg.pos,
            index = msg.index,
            round = C.round,
            opt = "select",
            sceneid = ret.sceneid,
            current = ret.current
        })
    end
    return {e = e}
end

function _H.legion_trial_choose(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    if check_reset(self) then return {e = 19} end
    if not legiond then return {e = 2} end
    local e, ret = skynet.call(legiond, "lua", "choose", self.rid, msg.pos)
    if e == 0 then
        local C = cache.get(self)
        flowlog.role(self, NM, {
            pos = msg.pos,
            round = C.round,
            opt = "choose",
            sceneid = ret.sceneid,
            current = ret.current
        })
    end
    return {e = e}
end

function _H.legion_trial_close(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    if check_reset(self) then return {e = 19} end
    if not legiond then return {e = 2} end
    local pos = msg.pos
    local e, ret = skynet.call(legiond, "lua", "close", self.rid, pos)
    if e == 0 then
        local C = cache.get(self)
        flowlog.role(self, NM, {
            pos = pos,
            round = C.round,
            opt = "close",
            sceneid = ret.sceneid,
            current = ret.current
        })
    end
    return {e = e}
end

function _H.legion_trial_buy(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    if check_reset(self) then return {e = 19} end
    if not legiond then return {e = 2} end
    local e, ret = skynet.call(legiond, "lua", "buy", self.rid, msg.pos,
        msg.index)
    if e == 0 then
        local C = cache.get(self)
        flowlog.role(self, NM, {
            pos = msg.pos,
            index = msg.index,
            round = C.round,
            opt = "buy",
            sceneid = ret.sceneid,
            current = ret.current
        })
    end
    return {e = 0}
end

function _H.legion_trial_transport(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    if check_reset(self) then return {e = 19} end
    if not legiond then return {e = 2} end
    local e, ret = skynet.call(legiond, "lua", "transport", self.rid, msg.pos)
    if e == 0 then
        local C = cache.get(self)
        flowlog.role(self, NM, {
            pos = msg.pos,
            round = C.round,
            opt = "transport",
            sceneid = ret.sceneid,
            current = ret.current
        })
    end
    return {e = 0}
end

function _LUA.legion_trial_battleover(self, ret)
    local reward
    if ret.win == wintype.win then
        local adds = uaward(ret.reward)
        local legiongoldadd = addition.sum(self, "legiongoldadd")
        if legiongoldadd > 0 then
            local cnt = adds.getcnt(awardtype.gold)
            cnt = math.floor(cnt * legiongoldadd / 1000 + 0.5)
            adds.append_one({awardtype.gold, 0, cnt})
        end

        local legioncoinadd = addition.sum(self, "legioncoinadd")
        if legioncoinadd > 0 then
            local cnt = adds.getcnt(awardtype.legion_coin)
            cnt = math.floor(cnt * legioncoinadd / 1000 + 0.5)
            adds.append_one({awardtype.legion_coin, 0, cnt})
        end
        reward = adds.result

        local option = {
            flag = "legion_trial_fight",
            arg1 = ret.objid,
            theme = "LEGIONTRIAL_FULL_THEME_",
            content = "LEGIONTRIAL_FULL_CONTENT_"
        }
        award.adde(self, option, reward)

        if ret.pass then task.trigger(self, "legion_" .. ret.floor) end
    end
    client.push(self, "legion_trial_battleend",
        {endinfo = battle.battle_endinfo(ret.ret, reward)})
    local C = cache.get(self)
    flowlog.role(self, NM, {
        pos = ret.pos,
        round = C.round,
        opt = "battleend",
        sceneid = ret.sceneid,
        current = ret.current
    })
end

function _H.legion_trial_fight(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    if check_reset(self) then return {e = 19} end

    local bi = msg.battle_info
    local list, list_save = m_battle.check_bi(self, bi, true)
    if not list then return {e = list_save} end

    local pos = msg.pos
    if not legiond then return {e = 2} end

    local e, ret = skynet.call(legiond, "lua", "fight", self.rid, pos, bi, list)
    if e == 0 then
        m_battle.set_lineup(self, NM, list_save)
        local C = cache.get(self)
        flowlog.role(self, NM, {
            pos = pos,
            round = C.round,
            opt = "fight",
            sceneid = ret.sceneid,
            current = ret.current
        })
    end
    return {e = e}
end

function _H.legion_trial_revive(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    if check_reset(self) then return {e = 19} end
    if not legiond then return {e = 2} end
    local item = BASIC.legion_trial_revive_item
    local option = {flag = "legion_trial_revive"}
    if not award.del(self, option, {item}) then return {e = 3} end
    local e, ret = skynet.call(legiond, "lua", "revive", self.rid)
    if e == 0 then
        local C = cache.get(self)
        flowlog.role(self, NM, {
            round = C.round,
            opt = "useitem",
            sceneid = ret.sceneid,
            current = ret.current
        })
    end
    return {e = e}
end

function _H.legion_trial_leave(self)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    skynet.call(legion_trialmgr, "lua", "leave", self.rid)
    legiond = nil
    return {e = 0}
end

function _M.add_card(self, id, cnt)
    if not fnopen.check_open(self, NM) then return 1 end
    if check_reset(self) then return 19 end
    skynet.call(legiond, "lua", "add_card", self.rid, id, cnt)
    return 0
end

function _M.robot_legion_trial_reset(self)
    if fnopen.check_open(self, NM) then
        skynet.call(legion_trialmgr, "lua", "reset", self.rid)
    end
    return {e = 0}
end

function _LUA.legion_trial_quit(self)
    legiond = nil
end

return _M
