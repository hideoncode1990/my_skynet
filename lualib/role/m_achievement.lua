local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local client = require "client.mods"
local _H = require "handler.client"
local cache = require "mongo.role"("achievement")
local progress = require "role.m_progress"
local fnopen = require "role.fnopen"
local award = require "role.award"
local ubit = require "util.bit"
local flowlog = require "flowlog"
local platlog = require "platlog"
local NM<const> = "achievement"

local CFG, LEVEL_CFG

skynet.init(function()
    CFG, LEVEL_CFG = cfgproxy("task_achieve", "task_achieve_level")
end)

require "role.mods" {
    name = NM,
    enter = function(self)
        client.enter(self, NM, "achievement_info", cache.get(self))
    end
}

function _H.achievement_finish(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local id = msg.id
    local cfg = CFG[id]
    if not cfg then return {e = 2} end
    local finish_list = cache.getsub(self, "finish_list")
    if ubit.get(finish_list, id) then return {e = 3} end
    if not progress.check(self, cfg.type, cfg.para) then return {e = 4} end
    ubit.set(finish_list, id)

    local C = cache.get(self)
    local points = C.points or 0
    C.points = points + cfg.point
    cache.dirty(self)
    flowlog.role_act(self, {flag = "achievement", arg1 = id, arg2 = "task"})
    platlog("achievement", {achievement_id = id}, self)
    return {e = 0, id = id}
end

function _H.achievement_getaward(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local id = msg.id
    local cfg = LEVEL_CFG[id]
    if not cfg then return {e = 2} end
    local award_list = cache.getsub(self, "award_list")
    if ubit.get(award_list, id) then return {e = 3} end
    local points = cache.get(self).points or 0
    if points < cfg.active then return {e = 4} end
    ubit.set(award_list, id)
    cache.dirty(self)

    local option = {
        flag = "achievement",
        arg1 = id,
        theme = "ACHIEVEMENT_FULL_THEME",
        content = "ACHIEVEMENT_FULL_CONTENT"
    }
    award.adde(self, option, cfg.reward)
    flowlog.role_act(self, {flag = "achievement", arg1 = id, arg2 = "getaward"})
    return {e = 0, id = id}
end

