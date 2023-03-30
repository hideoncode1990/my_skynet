local skynet = require "skynet"
local mods = require "role.mods"
local getupvalue = require "debug.getupvalue_recursive"
local _MAS = require "handler.master"
local utime = require "util.time"
local utable = require "util.table"
local cfgproxy = require "cfg.proxy"

local NM<const> = "mainline"

local BASIC
skynet.init(function()
    BASIC = cfgproxy("basic")
end)

-- 将时间戳全部重置成now
function _MAS.mainline(self)
    local mod = mods.get(nil, NM)
    local cache = getupvalue(mod.load, "cache")
    local now = utime.time_int()
    local C = cache.get(self)

    C.update = now
    C.expire = C.update + BASIC.mainline_maxtime + C.helptime

    local new = {}
    for _nm in pairs(utable.sub(C, "common_update")) do new[_nm] = now end
    C.common_update = new

    if C.support_update then C.support_update = now end

    if C.extra_update then C.extra_update = now end

    if C.support_update then C.support_update = now end

    C.reward = {}
    C.reward_add = {}
    cache.dirty(self)

    mod.enter(self)
    return {e = 0}
end
