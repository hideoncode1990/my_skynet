local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local utime = require "util.time"
local cache = require "guild.cache"("logs")
local _GUILDM = require "guild.m"
local _LUA = require "handler.lua"

local BASE
skynet.init(function()
    BASE = cfgproxy("basic")
end)

function _LUA.query_logs()
    local logs = cache.get()
    return true, 0, logs
end

return function(type, ...)
    local ti = utime.time()
    local logs = cache.get()
    local args = {}
    for _, d in ipairs({...}) do table.insert(args, tostring(d)) end
    table.insert(logs, 1, {ti = ti, type = type, args = args})
    local max = BASE.guild_log_max
    while #logs > max do table.remove(logs, #logs) end
    cache.dirty()
    _GUILDM.push2all("guild_log_tips", {})
end
