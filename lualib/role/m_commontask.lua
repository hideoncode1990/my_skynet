local skynet = require "skynet"
local client = require "client.mods"
local cfgproxy = require "cfg.proxy"
local fnopen = require "role.fnopen"
local task = require "task"
local award = require "role.award"
local flowlog = require "flowlog"
local platlog = require "platlog"
local taskcode = require "platlog.code.task"
local utime = require "util.time"
local event = require "role.event"
local mods = require "role.mods"

local _H = require "handler.client"

local insert = table.insert

local dnm<const>, wnm<const> = "dailytask", "weektask"

local CTX = {
    [dnm] = {check = utime.same_day, type = 1},
    [wnm] = {check = utime.same_week, type = 2}
}

local update_check

local CFG_ACTIVE, CFG_REWARD
skynet.init(function()
    CFG_ACTIVE, CFG_REWARD = cfgproxy("task_active", "task_active_reward")
end)

for NM, ctx in pairs(CTX) do
    local cache, pack
    skynet.init(function()
        ctx.CFG = cfgproxy("task_" .. NM)

        cache = require("mongo.role")(NM)
        ctx.cache = cache
        fnopen.reg(NM, NM, function(self)
            client.enter(self, NM, NM .. "_info", pack(self))
        end)
    end)

    pack = function(self)
        local C = cache.get(self)
        return {
            progress = task.cache(self, C.progress, NM),
            got = C.got,
            reward = C.reward,
            active = C.active,
            mainline = C.mainline
        }
    end

    mods {
        name = NM,
        enter = function(self)
            if fnopen.check_open(self, NM) then
                update_check(self, NM)
                client.enter(self, NM, NM .. "_info", pack(self))
            end
        end
    }

    task.reg(NM, function(self, ttype, val)
        if not fnopen.check_open(self, NM) then return end
        local tp, isstring = task.type(ttype)
        if isstring then
            if not ctx.CFG.type[tp] then return end

            local finish = cache.getsub(self, "finish")
            if finish[tp] then return end
        end
        local progress = cache.getsub(self, "progress")

        local ret = task.calc(ttype, progress, val, NM)
        if next(ret) then
            cache.dirty(self)
            for k, v in pairs(ret) do
                client.push(self, NM, NM .. "_change", {type = k, val = v})
            end
        end
    end)

    event.reg("EV_UPDATE", NM, function(self)
        if not fnopen.check_open(self, NM) then return end
        local new = update_check(self, NM)
        if new then client.enter(self, NM, NM .. "_info", pack(self)) end
    end)
end

update_check = function(self, NM)
    local ctx = CTX[NM]
    local cache = ctx.cache
    local C = cache.get(self)
    local now = utime.time_int()
    local new
    if not ctx.check(now, (C.update or 0)) then
        C.progress = nil
        C.got = nil
        C.finish = nil
        C.active = nil
        C.reward = nil
        C.update = now
        C.mainline = self.mainline
        cache.dirty(self)
        new = true
    end
    return new
end

local function finish(self, NM, id)
    if not fnopen.check_open(self, NM) then return {e = 1} end

    local ctx = CTX[NM]
    local CFG = ctx.CFG
    local cfg = CFG[id]
    local cache = ctx.cache

    local got = cache.getsub(self, "got")
    local got_dict = {}
    for _, v in ipairs(got) do
        if v == id then return {e = 2} end
        got_dict[v] = true
    end

    local tp = cfg.type
    local progress = cache.getsub(self, "progress")
    if not task.check(tp, cfg.para, progress, NM) then return {e = 3} end

    insert(got, id)
    local C = cache.get(self)
    local active = C.active or 0
    active = active + cfg.active
    C.active = active
    cache.dirty(self)

    if cfg.g_active then
        award.add(self, {flag = NM .. "_finish"}, {cfg.g_active})
    end

    local fin = 1
    for _id in pairs(CFG.type[tp]) do
        if not got_dict[_id] then
            fin = nil
            break
        end
    end
    if fin then cache.getsub(self, "finish")[tp] = 1 end

    client.push(self, NM, NM .. "_change", {active = active})
    flowlog.role_act(self, {flag = NM .. "_finish", arg1 = id, arg2 = active})
    platlog("finishtask", {task_type = taskcode[NM], task_id = id, result = 1},
        self)
    return {e = 0}
end

local function calc_reward(self, group)
    local mainline, cfg = self.mainline, CFG_REWARD[group]
    for _, _mainline in ipairs(cfg.arr) do
        if mainline >= _mainline then return cfg.info[_mainline] end
    end
    assert(false)
end

local function reward(self, NM, active)
    if not fnopen.check_open(self, NM) then return {e = 1} end

    local ctx = CTX[NM]
    local group = CFG_ACTIVE[ctx.type][active]
    if not group then return {e = 2} end

    local cache = ctx.cache
    local _reward = cache.getsub(self, "reward")
    for _, v in ipairs(_reward) do if v == active then return {e = 3} end end

    local cfg_reward = calc_reward(self, group)
    insert(_reward, active)
    cache.dirty(self)

    local option = {flag = NM .. "_reward", arg1 = active}
    flowlog.role_act(self, option)

    local UPPER = string.upper(NM)
    option.theme = UPPER .. "_FULL_THEME_"
    option.content = UPPER .. "_FULL_CONTENT_"
    award.adde(self, option, cfg_reward)
    return {e = 0}
end

function _H.dailytask_finish(self, msg)
    return finish(self, dnm, msg.id)
end

function _H.weektask_finish(self, msg)
    return finish(self, wnm, msg.id)
end

function _H.dailytask_reward(self, msg)
    return reward(self, dnm, msg.active)
end

function _H.weektask_reward(self, msg)
    return reward(self, wnm, msg.active)
end

