local skynet = require "skynet"
local client = require "client"
local _H = require "handler.client"
local _LUA = require "handler.lua"
local utime = require "util.time"
local fnopen = require "role.fnopen"
local guild = require "guild"
local utable = require "util.table"
local uaward = require "util.award"
local award = require "role.award"
local rdrop = require "role.drop"
local cfgproxy = require "cfg.proxy"
local cfgdata = require "cfg.data"
local event = require "role.event"
local m_battle = require "role.m_battle"
local battle = require "battle"
local addition = require "role.addition"
local flowlog = require "flowlog"
local cache = require("mongo.role")("guild_boss")
local schema = require "mongo.schema"
cache.schema(schema.SAR())
local win_type = require "battle.win_type"
local m_report = require "role.m_report"
local awardtype = require "role.award.type"
local task = require "task"

local NM<const> = "guild_boss"
local CFG
skynet.init(function()
    CFG = cfgproxy("guild_boss")
end)

local function send_info(self)
    local C = cache.get(self)
    client.push(self, "guild_boss_infos", {infos = C})
end

local function check_update(self, check_acttime)
    if not guild.in_guild(self) then return end
    local dirty
    if fnopen.check_open(self, NM) then
        local C = cache.get(self)
        local now = utime.time()
        local act_cache
        if check_acttime then
            local r = guild.call("guild_boss_get_acttime", self.rid)
            if r then act_cache = r end
        end
        for id, cfg in pairs(CFG) do
            local data = C[id]
            if not data then
                data = {id = id, times = 0, up_time = now}
                if cfg.exist_time then data.endtime = 0 end
                C[id] = data
                dirty = true
            end
            if act_cache and cfg.exist_time and data.endtime ~= act_cache[id] then
                data.up_time = now
                data.endtime = act_cache[id]
                dirty = true
            end
            -- 免费boss需要每日刷新
            if not cfg.exist_time and not utime.same_day(now, data.up_time) then
                data.up_time = now
                data.times = 0
                dirty = true
            end
        end
        if dirty then cache.dirty(self) end
    end
    return dirty
end

guild.reg({
    load = function(self)
        check_update(self, true)
    end,
    enter = function(self)
        if fnopen.check_open(self, NM) then send_info(self) end
    end,
    retry = function(self)
        if check_update(self, true) then send_info(self) end
    end
}, NM)

function _H.guild_boss_open(self, msg)
    if not guild.in_guild(self) then return {e = 1} end
    if not fnopen.check_open(self, NM) then return {e = 2} end
    local id = msg.id
    local ok, e = guild.call("guild_boss_open", self.rid, id)
    if not ok then return {e = e} end
    flowlog.role(self, "guild", {
        flag = "guild_boss_open",
        gid = self.gid,
        gname = self.gname,
        arg1 = id
    })
    return {e = 0}
end

local function calc_reward(self, id, total_damage)
    local cfg = cfgdata["guild_boss_reward_" .. id]
    for i = #cfg, 1, -1 do
        local v = cfg[i]
        local damage = v.damage
        if total_damage >= damage then
            local adds =
                uaward(utable.copy(v.reward)).append(rdrop.calc(v.drop))
            local guildcoinadd = addition.sum(self, "guildcoinadd")
            if guildcoinadd > 0 then
                local cnt = adds.getcnt(awardtype.guild_coin)
                cnt = math.floor(cnt * guildcoinadd / 1000)
                adds.append_one({awardtype.guild_coin, 0, cnt})
            end
            return adds
        end
    end
end

local function check_act_time(data)
    local now = utime.time()
    if data.endtime and now > data.endtime then return false end
    return true
end

function _H.guild_boss_fight(self, msg)
    if not guild.in_guild(self) then return {e = 1} end
    if not fnopen.check_open(self, NM) then return {e = 2} end
    local id = msg.id
    local C = cache.get(self)
    local data = C[id]
    if not check_act_time(data) then return {e = 3} end
    local times = data.times
    local max_times = addition.sum(self, "guild_boss_times_" .. id)
    if times >= max_times then return {e = 4} end

    local bi = msg.battle_info
    bi.multi_speed = bi.multi_speed
    local list, list_save = m_battle.check_bi(self, bi)
    if not list then return {e = list_save} end
    local left, err = m_battle.create_heroes(self, list)
    if not left then return {e = err} end
    local cfg = CFG[id]
    local right = m_battle.create_monsters(cfg.mon_group)
    local ctx<close> = battle.create(NM, cfg.mapid, {
        auto = bi.auto,
        multi_speed = bi.multi_speed,
        no_play = bi.no_play,
        save = true,
        win = win_type.win -- 强制战斗结果为true
    })
    if not battle.join(ctx, self) then return {e = 106} end
    m_battle.set_lineup(self, NM, list_save)
    battle.start(ctx, left, right, function(_ok, ret)
        if not _ok then return battle.abnormal_push(self) end
        if ret.restart or ret.terminate then
            return battle.push(self, ret)
        end
        assert(ret.win)
        data.times = data.times + 1
        local total_damage = 0
        local report = ret.report
        for _, v in pairs(report.left.heroes) do
            total_damage = total_damage + v.damage
        end
        data.damage = total_damage
        local max_damage = data.max_damage or 0
        if total_damage > max_damage then data.max_damage = total_damage end
        cache.dirty(self)

        local adds = calc_reward(self, id, total_damage)
        local reward = adds.result
        local option = {
            flag = "guild_boss_fight",
            arg1 = id,
            arg2 = total_damage,
            theme = "GUILDBOSS_FULL_THEME_",
            content = "GUILDBOSS_FULL_CONTENT_"
        }
        award.adde(self, option, reward)

        guild.send("guild_boss_battle_result", self.rid, id, {
            rid = self.rid,
            rname = self.rname,
            level = self.level,
            sid = self.sid,
            damage = total_damage,
            uuid = report.uuid,
            ver = data.endtime
        }, report)
        client.push(self, "guild_boss_result", {
            id = id,
            damage = total_damage,
            endinfo = battle.battle_endinfo(ret, reward)
        })
        send_info(self)
        task.trigger(self, "guild_boss")
        flowlog.role(self, "guild", {
            flag = "guild_boss_fight",
            gid = self.gid,
            gname = self.gname,
            arg1 = id,
            arg2 = total_damage
        })
    end)
    return {e = 0}
end

function _H.guild_boss_mopup(self, msg)
    if not guild.in_guild(self) then return {e = 1} end
    if not fnopen.check_open(self, NM) then return {e = 2} end
    local id = msg.id
    local cfg = CFG[id]
    if cfg.fnopen_mopup then
        if not fnopen.check_open(self, cfg.fnopen_mopup) then
            return {e = 3}
        end
    end
    local C = cache.get(self)
    local data = C[id]
    local times = data.times or 0
    local max_times = addition.sum(self, "guild_boss_times_" .. id)
    if times >= max_times then return {e = 4} end
    if not data.damage then return {e = 5} end
    if not check_act_time(data) then return {e = 6} end
    data.times = times + 1
    cache.dirty(self)
    local total_damage = data.damage
    local adds = calc_reward(self, id, total_damage)
    local option = {
        flag = "guild_boss_mopup",
        arg1 = id,
        arg2 = total_damage,
        theme = "GUILDBOSS_FULL_THEME_",
        content = "GUILDBOSS_FULL_CONTENT_"
    }
    award.adde(self, option, adds.result)
    send_info(self)
    task.trigger(self, "guild_boss")
    flowlog.role(self, "guild", {
        flag = "guild_boss_mopup",
        gid = self.gid,
        gname = self.gname,
        arg1 = id,
        arg2 = total_damage
    })
    return {e = 0, reward = adds.pack()}
end

function _H.guild_boss_query_records(self, msg)
    if not guild.in_guild(self) then return {e = 1} end
    if not fnopen.check_open(self, NM) then return {e = 2} end
    local id = msg.id
    local records = guild.call("guild_boss_records", self.rid, id)
    return {e = 0, records = records or {}}
end

function _LUA.guild_boss_endtime(self, d)
    local id = d.id
    local C = cache.get(self)
    local data = C[id]
    data.times = 0
    data.endtime = d.endtime
    cache.dirty(self)
    send_info(self)
end

event.reg("EV_UPDATE", NM, function(self)
    if check_update(self) then send_info(self) end
end)

event.reg("EV_GUILD_JOIN", NM, function(self)
    check_update(self, true)
    send_info(self)
end)

m_report.reg(NM, function(self, uuid)
    local report = guild.call("guild_boss_report", self.rid, uuid)
    return report
end)
