local cache = require("mongo.role")("baseinfo")
local client = require "client.mods"
local roleinfo = require "roleinfo.change"
local uniq = require "uniq.c"
local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local event = require "role.event"
local utime = require "util.time"
local flowlog = require "flowlog"
local condition = require "role.condition"
local ctype = require "role.condition.type"
local zset = require "zset"
local zsettype = require "zset.type"
local platlog = require "platlog"
local lock = require("skynet.queue")()
local award = require "role.award"
local task = require "task"
local awardtype = require "role.award.type"
local namecheck = require "role.namecheck"
local rolehelp = require "mongo.rolehelp"
local herobest = require "hero.best"

local _H = require "handler.client"

local _M = {}

local NM<const> = "baseinfo"

local BASIC
skynet.init(function()
    BASIC = cfgproxy("basic")
end)

-- 升到下一级的累计时长
local function calc_lvlup_time(self, C, ti)
    local lvlup_time = (C.lvlup_time or 0) + ti - (self.lvlup_ti or C.logintime)
    return lvlup_time
end

function _M.levelchange(self, level, exp)
    local C = cache.get(self)
    C.level, C.exp = level, exp
    self.level = level
    local ti = utime.time_int()
    local lvlup_time = calc_lvlup_time(self, C, ti)
    C.lvlup_time = 0
    self.lvlup_ti = ti
    cache.dirty(self)
    roleinfo.change(self, "level", level)
    return lvlup_time
end

function _M.levelget(self)
    local C = cache.get(self)
    return C.level, C.exp
end

local login_logid
local function leave_log(self, ti)
    local uuid = login_logid
    login_logid = nil
    local C = cache.get(self)
    local online_time = (C.online_time or 0) + ti - (C.logintime or ti)
    C.leavetime = ti
    C.online_time = online_time
    C.lvlup_time = calc_lvlup_time(self, C, ti)
    cache.dirty(self)
    flowlog.logout(self, uuid, ti, online_time)
    platlog("logout", {
        online_times = online_time,
        value_amount = award.getcnt(self, awardtype.diamond),
        energy = 0
    }, self)

    local top5_heroes = herobest.get_top5_heroes(self)
    platlog("snapshot", {
        mainline = self.mainline,
        top_heroes = table.concat(top5_heroes, "|"),
        first_login = os.date("%X", C.daily_first_login),
        last_logout = os.date("%X", ti - 1)
    }, self, ti - 1)

end

local function enter_log(self, ti)
    if login_logid then leave_log(self, ti) end
    local C = cache.get(self)
    local old_logintime = C.logintime or ti
    C.logintime = ti
    C.lvlup_ti = ti
    local daily_first_login = C.daily_first_login or 0
    if not utime.same_day(daily_first_login, ti) then
        C.daily_first_login = ti
    end
    cache.dirty(self)

    login_logid = uniq.uuid()
    if not utime.same_day(ti, old_logintime) then task.trigger(self, "login") end

    flowlog.login(self, login_logid, {logintime = ti})
    platlog("rolelogin", {value_amount = award.getcnt(self, awardtype.diamond)},
        self)
    zset.set(zsettype.login, {id = self.rid, value = ti, sid = self.sid})
end

local function midnight_log(self)
    if self.online == true then lock(enter_log, self, utime.time_int()) end
end

require("role.mods") {
    name = NM,
    load = function(self)
        local C = cache.get(self)
        local level = C.level
        if not level then
            level = 1
            C.level, C.exp = level, 0
            cache.dirty(self)
        end
        self.level = level
        self.online = false
        roleinfo.changetable(self, {level = level, online = false})
    end,
    enter = function(self)
        local C = cache.get(self)
        local logintime = utime.time_int()
        self.online = true

        roleinfo.changetable(self, {logintime = logintime, online = true})
        lock(enter_log, self, logintime)
        cache.dirty(self)
        client.enter(self, NM, "role_object", {
            level = C.level,
            exp = C.exp,
            rid = self.rid,
            rname = self.rname,
            sid = self.sid,
            uid = self.uid
        })
    end,
    leave = function(self)
        local leavetime = utime.time_int()

        self.online = false
        roleinfo.changetable(self, {leavetime = leavetime, online = false})
        lock(leave_log, self, leavetime)
    end
}

condition.reg(ctype.role_level, function(self, role_level)
    return cache.get(self).level >= role_level
end)

event.reg("EV_UPDATE", "baseinfo", midnight_log)

local function name_change(self, rname, flag, need_cost)
    if rname == self.rname then return false, 7 end
    rname = namecheck(rname)
    if not rname then return false, 4 end

    if need_cost and
        not award.del(self, {flag = flag, arg1 = rname},
            {BASIC.name_change_cost}) then return false, 5 end

    assert(rolehelp.update(self.proxy, {rid = self.rid}, {rname = rname}))
    self.rname = rname
    event.occur("EV_NAMECHANGE", self, rname)
    roleinfo.changetable(self, {rname = rname})
    flowlog.role_act(self, {flag = flag, arg1 = rname})
    client.push(self, NM, "namechange", {name = rname})
end

function _H.name_change(self, msg)
    local ok, e = name_change(self, msg.name, "namechange", true)
    if not ok then return {e = e} end
    return {e = 0}
end

return _M
