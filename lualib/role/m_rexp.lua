local skynet = require "skynet"
local client = require "client"
local cfgproxy = require "cfg.proxy"
local award = require "role.award"
local awardtype = require "role.award.type"
local event = require "role.event"
local baseinfo = require "role.baseinfo"
local flowlog = require "flowlog"
local platlog = require "platlog"
local task = require "task"

local CFG
skynet.init(function()
    CFG = cfgproxy("player")
end)

local function role_levelup(self, lv, exp, exp_add)
    local lv_before = baseinfo.levelget(self)
    local lvlup_time = baseinfo.levelchange(self, lv, exp)
    client.push(self, "role_addexp", {exp = exp, level = lv, expadd = exp_add})
    local zdl = self.zdl
    if lv > lv_before then
        event.occur("EV_LVUP", self, lv, lv_before)
        task.trigger(self, "level", lv)
        platlog("levelup", {
            use_times = lvlup_time,
            role_level_af = lv,
            role_level_bf = lv_before,
            battle_power_bf = zdl
        }, self)
    end
end

local function set_flowlog(self, level, exp, expadd, option)
    flowlog.role(self, "exp", {
        opt = "add",
        exp = exp,
        level = level,
        expadd = expadd,
        flag = option.flag,
        arg1 = option.arg1,
        arg2 = option.arg2
    })
end

local function role_exp_add(self, exp_add, option)
    local lv, exp = baseinfo.levelget(self)
    if not CFG[lv + 1] then
        set_flowlog(self, lv, exp, exp_add, option)
    else
        while exp_add > 0 do
            local cfg = CFG[lv]
            local need_exp = cfg.exp
            local overflow = exp + exp_add - need_exp
            if overflow >= 0 then
                lv = lv + 1
                exp = 0
                exp_add = overflow
                if not CFG[lv + 1] then break end
            else
                exp = exp + exp_add
                exp_add = 0
            end
        end
        role_levelup(self, lv, exp, exp_add)
        set_flowlog(self, lv, exp, exp_add, option)
    end
end

local function exp_add(self, _, _, option, items)
    local cnt = 0
    for _, cfg in ipairs(items) do cnt = cnt + cfg[3] end
    assert(cnt > 0)
    role_exp_add(self, cnt, option)
    return true
end

award.reg {type = awardtype.rexp, add = exp_add}

event.reg("EV_LVUP", "levelup reward", function(self, level, level_before)
    for lvl = level_before + 1, level do
        local cfg = CFG[lvl]
        local reward = cfg.reward
        if reward then
            award.adde(self, {
                flag = "ROLE_LVLUP",
                arg1 = level,
                theme = {"ROLE_LVLUP_FULL_THEME_{1}_", lvl},
                content = {"ROLE_LVLUP_FULL_CONTENT_{1}_", lvl}
            }, reward)
        end
    end
end)
