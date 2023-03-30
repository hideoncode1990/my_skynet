local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local map = require "role.map"
local client = require "client.mods"
local LOCK = require("skynet.queue")()
local m_battle = require "role.m_battle"
local _H = require "handler.client"
local explore = require "role.m_explore"
local fnopen = require "role.fnopen"
local award = require "role.award"
local cache = require("mongo.role")("crack")
local event = require "role.event"
local utime = require "util.time"
local udrop = require "util.drop"
local _LUA = require "handler.lua"
local the_task = require "task"
local hinit = require "hero"
local flowlog = require "flowlog"
local utable = require "util.table"
local variable = require "variable"

local NM<const> = "crack"
local DAY<const> = 86400

local init_check
local BASIC, TASKGROUP, TASK, MAP, TASKPDF, MAPPDF, REWARD

skynet.init(function()
    BASIC, TASKGROUP, TASK, MAP, TASKPDF, MAPPDF, REWARD =
        cfgproxy("basic", "crack_taskgroup", "crack_task", "crack_map",
            "crack_taskpdf", "crack_mappdf", "crack_reward")

    fnopen.reg("crack", "crack", function(self)
        local C = cache.get(self)
        C.version = BASIC.crack_ver
        cache.dirty(self)
        init_check(self)
    end)
end)

local function make_no_order(tbl)
    local size = #tbl
    for i = 1, size do
        local temp = math.random(i, size)
        tbl[i], tbl[temp] = tbl[temp], tbl[i]
    end
    return tbl
end

local function task_new(self)
    local ret = {}

    local task_group
    for _, v in ipairs(TASKGROUP) do
        if self.mainline >= v.mainline then
            task_group = utable.copy(v.group_task)
            break
        end
    end

    make_no_order(task_group)

    for _, v in ipairs(task_group) do
        local taskkey = udrop.nexts(TASKPDF[v])
        local cfg = TASK[taskkey]
        local group_map = cfg.group_map
        local mapkey = udrop.nexts(MAPPDF[group_map])
        table.insert(ret, {taskkey = taskkey, mapkey = mapkey})
    end
    return ret
end

local function inner_reward(self, C, task, cfg_task)
    C.got = 1
    cache.dirty(self)

    local cfg_reward = REWARD[cfg_task.reward]
    local reward
    for _, v in ipairs(cfg_reward) do
        if C.mainline >= v.mainline then
            reward = v.reward
            break
        end
    end
    assert(reward)

    the_task.trigger(self, "crack_task")
    award.adde(self, {
        flag = "crack",
        arg1 = task.taskkey,
        arg2 = task.mapkey,
        theme = "CRACK_FULL_THEME_",
        content = "CRACK_FULL_CONTENT_"
    }, reward)
end

local function get_reward(self, C)
    local progress = C.progress
    if not progress or C.got or not C.current then return false end
    local task = C.tasks[C.current]
    local cfg_task, cfg_map = TASK[task.taskkey], MAP[task.mapkey]
    if progress >= cfg_map.condition then
        inner_reward(self, C, task, cfg_task)
        return true
    end
    return false
end

local function task_refresh(self, C, now)
    get_reward(self, C)
    C.tasks = task_new(self)
    C.mainline = self.mainline
    C.update = now
    C.current = nil
    C.progress = 0
    C.got = nil
    cache.dirty(self)
end

local function calc_period(time, starttime)
    local size = BASIC.crack_refresh * DAY
    starttime = utime.begin_day(starttime)
    local long = time - starttime
    local n = long // size + 1
    return n, n * size + starttime
end

local function init(self, C)
    local now = utime.time_int()
    local update = C.update
    local starttime = variable["starttime_" .. self.sid]
    local perid_now, overtime = calc_period(now, starttime)

    if not update or calc_period(update, starttime) ~= perid_now then
        explore.over(self)
        task_refresh(self, C, now)
    end
    return overtime
end

init_check = function(self)
    if not fnopen.check_open(self, NM) then return end

    local C = cache.get(self)
    local overtime = init(self, C)
    client.enter(self, NM, "crack_task", {
        tasks = C.tasks,
        current = C.current,
        progress = C.progress,
        got = C.got,
        mainline = C.mainline,
        overtime = overtime
    })
end

require("role.mods") {
    name = "crack",
    load = function(self)
        local C = cache.get(self)
        if fnopen.check_open(self, NM) and C.version ~= BASIC.crack_ver then
            C.version = BASIC.crack_ver
            cache.dirty(self)
            task_refresh(self, C, utime.time_int())
        end
    end,
    enter = init_check
}

local function crack_start(self, C, new)
    local task = C.tasks[C.current]
    local cfg_map = MAP[task.mapkey]

    local ctx = {
        rid = self.rid,
        owner = NM .. self.rid,
        new = new,
        mainline = self.mainline,
        mod_nm = NM,
        mapid = cfg_map.mapid,

        average_st = hinit.stage_top5_average(self),
        battle_mapid = cfg_map.battle,
        target = {
            taskkey = task.taskkey,
            mapkey = task.mapkey,
            call = "crack_progress"
        },
        fight_mode = 1
    }

    LOCK(explore.start, self, ctx)
    return 0
end

function _H.crack_task_choose(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local C = cache.get(self)
    local index = msg.index

    if C.current then return {e = 2} end
    if not C.tasks then return {e = 3} end
    local task = C.tasks[index]
    if not task then return {e = 4} end
    if task.done then return {e = 5} end

    C.current = index
    C.start_ti = utime.time_int()
    cache.dirty(self)
    return {e = crack_start(self, C, true)}
end

function _H.crack_task_finish(self)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local C = cache.get(self)
    local current = C.current
    if not C.current then return {e = 1} end
    if not C.tasks then return {e = 2} end
    local task = C.tasks[current]
    if not task then return {e = 3} end
    if task.done then return {e = 4} end

    get_reward(self, C)
    C.start_ti = nil
    C.current = nil
    C.got = nil
    C.progress = 0
    task.done = 1
    cache.dirty(self)
    LOCK(explore.over, self)
    return {e = 0}
end

function _H.crack_start(self)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    return {e = crack_start(self, cache.get(self))}
end

function _H.crack_get_reward(self)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local C = cache.get(self)
    if C.got then return {e = 2} end
    local task = C.tasks[C.current]
    local cfg_map = MAP[task.mapkey]
    if C.progress < cfg_map.condition then return {e = 3} end

    local cfg_task = TASK[task.taskkey]
    inner_reward(self, C, task, cfg_task)
    return {e = 0}
end

--[[
    100场景地址不存在
    101.场景玩家不在怪物点旁 102.怪物已死亡
    103.阵容中有不存在的英雄 104.阵容中有相同tab的英雄
    105.阵容中有死亡英雄 106.正在进行一场战斗
    107 补给值不足 108.超过阵容数量上限
    109.倍速功能未开放
--]]

function _H.crack_battle_start(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local bi = msg.battle_info

    local list, list_save = m_battle.check_bi(self, bi, true)
    if not list then return {e = list_save} end

    local ok, err = map.battle_start(self, msg.uuid, list, bi)
    if not ok then return {e = err} end

    m_battle.set_lineup(self, NM, list_save)
    return {e = 0}
end

function _LUA.crack_progress(self, progress, id, cnt, mapid)
    cache.get(self).progress = progress
    cache.dirty(self)
    client.push(self, NM, "crack_progress", {progress = progress})

    -- 添加日志
    local starttime = variable["starttime_" .. self.sid]
    local perid_now = calc_period(utime.time_int(), starttime)
    flowlog.role(self, NM, {
        perid = perid_now,
        mainline = self.mainline,
        mapid = mapid,
        progress = progress,
        id = id,
        cnt = cnt
    })
end

event.reg("EV_UPDATE", NM, init_check)
