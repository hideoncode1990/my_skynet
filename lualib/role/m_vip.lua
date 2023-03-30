local client = require "client.mods"
local cache = require("mongo.role")("vip")
local flowlog = require "flowlog"
local cfgproxy = require "cfg.proxy"
local award = require "role.award"
local event = require "role.event"
local addition = require "role.addition"
local condition = require "role.condition"
local ctype = require "role.condition.type"

local NM<const> = "vip"

local CFGVIP
require("skynet").init(function()
    CFGVIP = cfgproxy("vip")
end)

local _H = require "handler.client"

local function calc(self, C, add, nms, pkts, option)
    if not C then C = cache.get(self) end

    local level_prev, exp_prev = C.level, C.exp or 0
    local level, exp = level_prev or 0, exp_prev + add
    local cfg = CFGVIP[level]
    while true do
        local expmax = cfg.exp
        if exp >= expmax then
            cfg = CFGVIP[level + 1]
            if not cfg then break end

            level = level + 1
            exp = exp - expmax
        else
            break
        end
    end
    self.viplevel = level
    if level_prev ~= level or exp ~= exp_prev then
        C.level, C.exp = level, exp
        cache.dirty(self)
        if level > 0 and exp > 0 then
            flowlog.role(self, "vipexp", {
                flag = option.flag,
                arg1 = option.arg1,
                arg2 = option.arg2,
                viplevel_prev = level_prev or 0,
                viplevel = level,
                vipexp_prev = exp_prev,
                vipexp = exp,
                addexp = add
            })
        end
        if pkts then
            nms.vipexp_add = NM
            table.insert(pkts.vipexp_add,
                {change = add, level = C.level, exp = C.exp})
        end

        if level_prev ~= level then
            addition.dirty(self)
            event.occur("EV_VIP_LVUP", self, level, level_prev or 0)
        end
        return true
    end
end

local _M = {}

require "role.mods" {
    name = NM,
    load = function(self)
        local C = cache.get(self)
        calc(self, C, 0, nil, nil, {flag = "load"})
    end,
    enter = function(self)
        local C = cache.get(self)
        client.enter(self, NM, "vip_info", C)
    end
}

award.reg {
    type = require("role.award.type").vip_exp,
    add = function(self, nms, pkts, option, items)
        local exp = 0
        for _, item in ipairs(items) do exp = exp + item[3] end
        return calc(self, cache.get(self), exp, nms, pkts, option)
    end
}

function _H.vipaward(self, msg)
    local level = msg.level
    local C = cache.get(self)
    if C.level < level then return {e = 1} end

    local cfg = CFGVIP[level]
    local gift = cfg.gift
    if not gift then return {e = 2} end

    local awardinfo = C.awardinfo or 0
    local marks = (1 << level)

    if (awardinfo & marks) ~= 0 then return {e = 3} end

    C.awardinfo = awardinfo | marks
    cache.dirty(self)
    award.adde(self, {
        flag = "vipaward",
        arg1 = level,
        theme = "VIPAWARD_FULL_THEME_",
        content = "VIPAWARD_FULL_CONTENT_"
    }, gift)
    return {e = 0}
end

addition.reg("vip", function(self, key, cb)
    local level = cache.get(self).level
    local v = CFGVIP[level][key]
    if v then cb(v) end
end)

condition.reg(ctype.vip, function(self, viplevel)
    return cache.get(self).level >= viplevel
end)

function _M.get(self)
    return cache.get(self).level
end

return _M
