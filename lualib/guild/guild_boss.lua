local skynet = require "skynet"
local log = require "log"
local _LUA = require "handler.lua"
local cfgproxy = require "cfg.proxy"
local utime = require "util.time"
local log_t = require"guild.helper".log_t
local lang = require "lang"
local _GUILDM = require "guild.m"
local reportlib = require("report")("DB_FUNC", "report_guildboss")
local cache = require "guild.cache"("guild_boss")
local schema = require "mongo.schema"
cache.schema(schema.OBJ({
    acttime = schema.SAR(),
    records = schema.ARR(schema.ORI)
}))
local guildlog = require "guild.guildlog"

local CFG
skynet.init(function()
    CFG = cfgproxy("guild_boss")
end)

local function check_reset_record(gid, id)
    local records = cache.getsub("records")
    local list = records[id]
    local acttime = cache.getsub("acttime")
    local ver = acttime[id]
    if list and next(list) then
        local record = list[1]
        local cfg = CFG[id]
        if (cfg.exist_time and record.ver ~= ver) or
            not utime.same_day(record.ti, utime.time()) then
            reportlib.del({gid = gid, bossid = id})
            records[id] = {}
            cache.dirty()
        end
    end
end

function _LUA.guild_boss_open(role, id)
    check_reset_record(role.gid, id)
    local cfg = CFG[id]
    if not cfg or not cfg.exist_time then return false, 6 end

    local now = utime.time()
    local acttime = cache.getsub("acttime")
    local endtime = acttime[id] or 0
    if now < endtime then return false, 3 end

    if not _GUILDM.is_official(role) then return false, 4 end
    if not _LUA.del_contribution(role, cfg.open_cost) then return false, 5 end

    acttime[id] = now + cfg.exist_time
    cache.dirty()

    guildlog(log_t.act_open,
        lang(string.format("GUILD_BOSS_LOG_{1}_%d", id), role.rname))
    _GUILDM.send_emailall(lang("GUILD_BOSS_OPEN_THEME"),
        lang(string.format("GUILD_BOSS_OPEN_CONTENT_%d_{1}_%d", role.pos, id),
            role.rname), {flag = "guild_boss", arg1 = id})

    _GUILDM.send2all("send_online_agent", "guild_boss_endtime",
        {id = id, endtime = acttime[id]})
    return true, 0
end

function _LUA.guild_boss_get_acttime()
    local acttime = cache.getsub("acttime")
    return acttime
end

function _LUA.guild_boss_battle_result(role, id, record, report)
    local gid = role.gid
    check_reset_record(gid, id)
    local records = cache.getsub("records")
    local list = records[id] or {}
    record.ti = utime.time()
    table.insert(list, 1, record)
    assert(#list < 1000, "record too many")
    records[id] = list
    cache.dirty()
    report.gid = gid
    report.bossid = id
    reportlib.add(report)
end

function _LUA.guild_boss_records(role, id)
    check_reset_record(role.gid, id)
    local records = cache.getsub("records")
    return records[id]
end

function _LUA.guild_boss_report(role, uuid)
    local report = reportlib.query_one({uuid = uuid})
    return report
end
