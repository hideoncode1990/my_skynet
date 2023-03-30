local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local client = require "client"
local _H = require "handler.client"
local cache = require "mongo.role"("kf_sevensignin")
local award = require "role.award"
local utime = require "util.time"
local event = require "role.event"
local flowlog = require "flowlog"
local platlog = require "platlog"
local hinit = require "hero"

local NM<const> = "kf_sevensignin"
local DAY<const> = 86400

local schema = require "mongo.schema"

cache.schema(schema.OBJ {
    day = schema.ORI,
    update = schema.ORI,
    signin = schema.NOBJ()
})

local CFG, BASIC

skynet.init(function()
    CFG, BASIC = cfgproxy("kf_sevensignin", "basic")
end)

local STATE_SIGNIN<const> = 1
local STATE_GOT<const> = 2

local function in_activity(self, time)
    local startti = utime.begin_day(self.created)
    local diff = (time - startti) // DAY + 1
    return diff < BASIC.kf_sevensignin_over, diff
end

local function push_info(self, C)
    C.overtime = utime.begin_day(self.created) + DAY * #CFG
    client.push(self, "kf_sevensignin_info", C)
end

local function enter(self)
    local now = utime.time_int()
    local ok, i = in_activity(self, now)
    if not ok then return end

    local C = cache.get(self)
    local size = #CFG
    if i > size then return push_info(self, C) end

    local day, update = C.day or 0, C.update or 0
    local signin = cache.getsub(self, "signin")
    if not utime.same_day(update, now) then
        C.update = now
        day = day + 1
        C.day = day
        signin[day] = STATE_SIGNIN
        cache.dirty(self)
        platlog("activity", {activity_id = "sevensignin", sub_id = day}, self)
    end
    push_info(self, C)
end

require "role.mods" {name = NM, enter = enter}

function _H.kf_sevensignin_get(self, msg)
    local ok = in_activity(self, utime.time_int())
    if not ok then return {e = 1} end

    local day = msg.day
    local cfg = CFG[day]
    if not cfg then return {e = 2} end

    local signin = cache.getsub(self, "signin")
    local state = signin[day]
    if not state then return {e = 3} end
    if state == STATE_GOT then return {e = 4} end

    local reward = cfg.reward
    local newtab = hinit.check_new_tab(self, reward)

    local option = {flag = "kf_sevensignin_get", arg1 = day}
    local _ok, err = award.add(self, option, reward)
    if not _ok then return {e = err} end

    signin[day] = STATE_GOT
    cache.dirty(self)
    flowlog.role_act(self, option)
    return {e = 0, newtab = newtab}
end

event.reg("EV_UPDATE", NM, enter)
