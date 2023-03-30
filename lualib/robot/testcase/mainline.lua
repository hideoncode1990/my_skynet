local skynet = require "skynet"
local event = require "robot.event"
local net = require "robot.net"
local cfgproxy = require "cfg.proxy"
local fnopen = require "robot.fnopen"
local log = require "robot.log"
local herobag = require "robot.herobag"
local battle = require "robot.battle"
local fight_lock = require "robot.fight_lock"
local logerr = require "log.err"

local C
local _H = require "handler.client"
local _M = {}

local NM<const> = "mainline"
local function get_reward(self)
    local ret = net.request(self, 100, "mainline_get_reward")
    log(self, {opt = "mainline_get_reward", e = ret and ret.e or ret})
    return ret.e
end

local function support(self)
    local ret = net.request(self, 100, "mainline_support")
    local e = ret and ret.e
    log(self, {opt = "mainline_support", e = e or false})

    if e == 0 then C.support = ret.support end
    return e
end

local function do_support(self)
    while true do
        local e = support(self)
        if e == 0 then
            skynet.sleep(100)
        else
            return
        end
    end
end

local inreward
local function do_get_reward(self)
    if inreward then return end
    inreward = true
    while true do
        skynet.sleep(30 * 60 * 100)
        get_reward(self)
    end
end

-- 服务器上线 或 跨天会推送 mainline_info,
-- 然后尝试 领取挂机奖励和快速支援
function _H.mainline_info(self, msg)
    C = msg
    log(self, {opt = "mainline_info", mainline = msg.id})
    get_reward(self)
    do_support(self)
end

function _H.mainline_win(self, msg)
    local id = msg.id
    C.id = id
    log(self, {opt = "mainline_win", mainline = id})
    event.occur("mainline_win", self, id)
end

function _H.mainline_result(self, msg)
    return battle.over(self, true, msg)
end

local function get_lineup(self)
    local top = herobag.calc_stage_top5(self)
    local lineup = {}
    for k, uuid in ipairs(top) do
        local info = herobag.query(self, uuid)
        table.insert(lineup, {
            pos = k,
            uuid = uuid,
            stage = info.stage,
            level = info.level,
            lvreal = info.lvreal
        })
    end
    return lineup
end

function _M.query(self)
    return C.id
end

event.reg("mainline_win", get_reward) -- 通关尝试领取挂机奖励

local function fight_inner(self)
    local battle_info = {
        list = get_lineup(self),
        auto = true,
        save = true,
        multi_speed = battle.get_accelerate(self)
    }
    local ret = net.request(self, 100, "mainline_fight",
        {battle_info = battle_info})

    local e = ret.e
    if e == 0 then
        return battle.wait(self, {nm = NM})
    else
        return false, e
    end
end

local function do_fight(self)
    local ok, err = fight_lock(fight_inner, self)
    if ok then
        print("mainline_fight_successfully")
    else
        print("mianline_fight_failed err:", err)
    end
end

function _M.onlogin(self)
    skynet.fork(do_get_reward, self)
    do_fight(self)
end

return _M
