local skynet = require "skynet"
local cache = require("mongo.role")("capacity")
local cfgproxy = require "cfg.proxy"
local flowlog = require "flowlog"
local award = require "role.award"
local client = require "client"
local addition = require "role.addition"
local _H = require "handler.client"

local _M = {}

local NM<const> = "capacity"

local CFG, BASIC

skynet.init(function()
    CFG, BASIC = cfgproxy("herobag", "basic")
end)

require "role.mods" {
    name = NM,
    enter = function(self)
        client.push(self, "capacity_lv", {capacity_lv = cache.get(self).level})
    end
}

function _M.get(self)
    local level = cache.get(self).level
    local max = BASIC.hero_max
    return (level and max + CFG[level].amount or max) +
               addition.sum(self, "capacity")
end

function _H.capacity_buy(self)
    local C = cache.get(self)
    local level = C.level or 0
    local tar_level = level + 1
    local cfg = CFG[tar_level]
    if not cfg then return {e = 1} end

    local option = {flag = "capacity_buy", arg1 = tar_level}

    local ok, e = award.del(self, option, {cfg.cost})
    if not ok then return {e = e} end

    C.level = tar_level
    cache.dirty(self)
    flowlog.role_act(self, option)
    return {e = 0, capacity_lv = tar_level}
end

return _M
