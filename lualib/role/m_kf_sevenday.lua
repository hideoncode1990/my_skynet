local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local client = require "client"
local task = require "task"
local _H = require "handler.client"
local cache = require "mongo.role"("kf_sevenday")
local award = require "role.award"
local ubit = require "util.bit"
local utime = require "util.time"
local event = require "role.event"
local flowlog = require "flowlog"
local platlog = require "platlog"
local taskcode = require "platlog.code.task"
local hinit = require "hero"

local NM<const> = "kf_sevenday"
local DAY<const> = 24 * 60 * 60

local CFG, CFG_HUOYUE, CFG_TYPE, BASIC

local function in_activity(self)
    local startti = utime.begin_day(self.created)
    local diff = (utime.time() - startti) // DAY + 1
    return diff <= BASIC.kf_sevenday_over, diff
end

local function check_send(self, tp, val)
    client.push(self, "kf_sevenday_change", {tp = tp, val = val})
end

skynet.init(function()
    CFG, CFG_HUOYUE, CFG_TYPE, BASIC = cfgproxy("task_kf_sevenday",
        "task_kf_sevenday_huoyue", "task_kf_sevenday_type", "basic")
end)

local reged
require "role.mods" {
    name = NM,
    load = function(self)
        if not reged and in_activity(self) then
            reged = true
            task.reg(NM, function(self, tp, val)
                local _type, isstring = task.type(tp)
                if isstring and not CFG_TYPE[_type] then return end

                local tasks = cache.getsub(self, "tasks")
                local ret = task.calc(tp, tasks, val, NM)
                if next(ret) then
                    cache.dirty(self)
                    for k, v in pairs(ret) do
                        check_send(self, k, v)
                    end
                end
            end)
        end
    end,
    enter = function(self)
        if in_activity(self) then
            local C = cache.get(self)
            client.push(self, "kf_sevenday_info", {
                finish_list = C.finish_list,
                award_list = C.award_list,
                points = C.points,
                tasks = task.cache(self, C.tasks, NM),
                created = self.created
            })
        end
    end
}

function _H.kf_sevenday_finish(self, msg)
    local ok, diff = in_activity(self)
    if not ok then return {e = 1} end
    local id = msg.id
    local cfg = CFG[id]
    if not cfg then return {e = 2} end
    if diff < cfg.day then return {e = 3} end
    local finish_list = cache.getsub(self, "finish_list")
    if ubit.get(finish_list, id) then return {e = 4} end
    local tp = cfg.type
    local tasks = cache.getsub(self, "tasks")
    if not task.check(tp, cfg.para, tasks, NM) then return {e = 5} end
    local err
    ok, err = award.add(self, {flag = "kf_sevenday_finish", arg1 = id},
        cfg.reward)
    if not ok then return {e = err} end
    ubit.set(finish_list, id)
    local C = cache.get(self)
    local points = C.points or 0
    C.points = points + cfg.active
    cache.dirty(self)
    flowlog.role_act(self, {flag = "sevenday_task", arg1 = id})
    platlog("finishtask",
        {task_type = taskcode.sevendaytask, task_id = id, result = 1}, self)
    return {e = 0, id = id}
end

function _H.kf_sevenday_getaward(self, msg)
    local ok = in_activity(self)
    if not ok then return {e = 1} end
    local id = msg.id
    local cfg = CFG_HUOYUE[id]
    if not cfg then return {e = 2} end
    local award_list = cache.getsub(self, "award_list")
    if ubit.get(award_list, id) then return {e = 3} end
    local C = cache.get(self)
    local points = C.points or 0
    if points < cfg.active then return {e = 4} end

    local reward = cfg.reward
    local newtab = hinit.check_new_tab(self, reward)
    local err
    ok, err =
        award.add(self, {flag = "kf_sevenday_getaward", arg1 = id}, reward)
    if not ok then return {e = err} end
    ubit.set(award_list, id)
    cache.dirty(self)
    flowlog.role_act(self, {flag = "sevenday_task_getaward", arg1 = id})
    return {e = 0, id = id, newtab = newtab}
end

event.reg("EV_UPDATE", NM, function(self)
    if not in_activity(self) then task.unreg(NM) end
end)
