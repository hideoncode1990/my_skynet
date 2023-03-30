local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local fnopen = require "role.fnopen"
local _H = require "handler.client"
local cache = require("mongo.role")("mainstory")
local client = require "client.mods"
local ubit = require "util.bit"
local award = require "role.award"
local uaward = require "util.award"
local NM = "mainstory"

local CFG
skynet.init(function()
    CFG = cfgproxy("mainstory")
end)

require("role.mods") {
    name = NM,
    enter = function(self)
        local C = cache.get(self)
        client.enter(self, NM, "mainstory_info", {played_list = C.played_list})
    end
}

function _H.mainstory_played(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local id = msg.id
    local cfg = CFG[id]
    if not cfg then return {e = 2} end
    local played_list = cache.getsub(self, "played_list")
    if ubit.get(played_list, id) then return {e = 3} end

    local conds = cfg.condition
    for _, cond in ipairs(conds) do
        local tp, val = cond[1], cond[2]
        if tp == 1 then
            local mainline = self.mainline
            if mainline < val then return {e = 4} end
        elseif tp == 2 then
            if not ubit.get(played_list, val) then return {e = 5} end
        end
    end
    ubit.set(played_list, id)
    cache.dirty(self)
    local option = {
        flag = NM,
        arg1 = id,
        theme = "STORY_FULL_THEME",
        content = "STORY_FULL_CONTENT"
    }
    local reward = cfg.reward
    award.adde(self, option, reward)
    return {e = 0, items = uaward.pack(reward)}
end
