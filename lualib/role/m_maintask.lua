local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local client = require "client"
local _H = require "handler.client"
local cache = require "mongo.role"("maintask")
local progress = require "role.m_progress"
local fnopen = require "role.fnopen"
local award = require "role.award"
local ubit = require "util.bit"
local flowlog = require "flowlog"
local platlog = require "platlog"
local taskcode = require "platlog.code.task"
local NM<const> = "maintask"

local CFG

skynet.init(function()
    CFG = cfgproxy("task_maintask")
end)

require "role.mods" {
    name = NM,
    enter = function(self)
        local finish_list = cache.getsub(self, "finish_list")
        client.push(self, "maintask_info", {finish_list = finish_list})
    end
}

function _H.maintask_finish(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local id = msg.id
    local cfg = CFG[id]
    if not cfg then return {e = 2} end
    local finish_list = cache.getsub(self, "finish_list")
    local preid = cfg.preid
    if ubit.get(finish_list, id) then return {e = 3} end
    if preid and not ubit.get(finish_list, preid) then return {e = 4} end
    if not progress.check(self, cfg.type, cfg.para) then return {e = 5} end
    ubit.set(finish_list, id)
    cache.dirty(self)

    flowlog.role_act(self, {flag = "maintask", arg1 = id})
    platlog("finishtask",
        {task_type = taskcode.maintask, task_id = id, result = 1}, self)
    local option = {
        flag = "maintask",
        arg1 = id,
        theme = "MAINTASK_FULL_THEME",
        content = "MAINTASK_FULL_CONTENT"
    }
    award.adde(self, option, cfg.reward)
    return {e = 0}
end

