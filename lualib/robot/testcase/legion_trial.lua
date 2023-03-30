local skynet = require "skynet"
local event = require "robot.event"
local net = require "robot.net"
local cfgproxy = require "cfg.proxy"
local _H = require "handler.client"
local fnopen = require "robot.fnopen"
local utable = require "util.table"
local herobag = require "robot.herobag"
local utime = require "util.time"
local battle = require "robot.battle"
local objtype = require "legion_trial.objtype"
-- local log = require "log"
local chat = require "robot.chat"

local NM<const> = "legion_trial"
local C
local _H = require "handler.client"
local _M = {}

local DATA
local CFG_OBJ, CFG_POS
skynet.init(function()
    CFG_OBJ, CFG_POS = cfgproxy("legion_trial_objs", "legion_trial")
end)

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

local function log()
end

local action = {
    [objtype.hero] = function(self, pos, para)
        local index = math.random(para[1])
        local ret = net.request(self, 100, "legion_trial_select",
            {pos = pos, index = index})
        log(
            "%s legion_hero pos=%d,sceneid=%d,current=%d,choosed=%d,index=%d,e=%d",
            self.rname, pos, DATA.sceneid, DATA.current, DATA.choosed or -1,
            index, ret.e)
        return ret
    end,
    [objtype.monster] = function(self, pos)
        local battle_info = {
            list = get_lineup(self),
            auto = true,
            skip = true,
            multi_speed = battle.get_accelerate(self)
        }
        if DATA.choosed ~= pos then
            local ret = net.request(self, 100, "legion_trial_choose",
                {pos = pos})
            if ret.e == 0 then
                DATA.choosed = pos
            else
                return ret
            end
        end
        local ret = net.request(self, 100, "legion_trial_fight",
            {pos = pos, battle_info = battle_info})
        log(
            "%s legion_monster_fight pos=%d,sceneid=%d,current=%d,choosed=%d,e=%d",
            self.rname, pos, DATA.sceneid, DATA.current, DATA.choosed or -1,
            ret.e)
        if ret.e == 0 then
            local _, msg = battle.wait(self, {nm = NM})
            if msg.endinfo.win == 0 then
                if math.random(1000) < 500 then return {e = 999} end
            end
        end
        return ret
    end,
    [objtype.box] = function(self, pos, para)
        local ret = net.request(self, 100, "legion_trial_select", {pos = pos})
        log("%s legion_box pos=%d,sceneid=%d,current=%d,choosed=%d,e=%d",
            self.rname, pos, DATA.sceneid, DATA.current, DATA.choosed or -1,
            ret.e)
        return ret
    end,
    [objtype.revive] = function(self, pos, para)
        local ret = net.request(self, 100, "legion_trial_select", {pos = pos})
        log("%s legion_revive pos=%d,sceneid=%d,current=%d,choosed=%d,e=%d",
            self.rname, pos, DATA.sceneid, DATA.current, DATA.choosed or -1,
            ret.e)
        return ret
    end,
    [objtype.recover] = function(self, pos, para)
        local ret = net.request(self, 100, "legion_trial_select", {pos = pos})
        log("%s legion_recover pos=%d,sceneid=%d,current=%d,choosed=%d,e=%d",
            self.rname, pos, DATA.sceneid, DATA.current, DATA.choosed or -1,
            ret.e)
        return ret
    end,
    [objtype.shop] = function(self, pos, para)
        if not DATA.choosed then
            local ret = net.request(self, 100, "legion_trial_choose",
                {pos = pos})
            log("%s legion_shop pos=%d,sceneid=%d,current=%d,choosed=%d,e=%d",
                self.rname, pos, DATA.sceneid, DATA.current, DATA.choosed or -1,
                ret.e)
            if ret.e == 0 then DATA.choosed = pos end
            return ret
        else
            if math.random(1000) < 500 then
                local obj = DATA.objs[pos]
                local selects = obj.selects
                local r = math.random(#selects)
                for i = 1, 4 do
                    local index = (r % 4) + 1
                    local item = selects[index]
                    if not item.selected then
                        local ret = net.request(self, 100, "legion_trial_buy",
                            {pos = pos, index = index})
                        log(
                            "%s legion_shop_buy pos=%d,sceneid=%d,current=%d,choosed=%d,index=%d,e=%d",
                            self.rname, pos, DATA.sceneid, DATA.current,
                            DATA.choosed or -1, index, ret.e)
                    end
                    r = r + 1
                end
            end
            local ret =
                net.request(self, 100, "legion_trial_close", {pos = pos})
            log(
                "%s legion_shop_close pos=%d,sceneid=%d,current=%d,choosed=%d,e=%d",
                self.rname, pos, DATA.sceneid, DATA.current, DATA.choosed or -1,
                ret.e)
            return ret
        end
    end,
    [objtype.buff] = function(self, pos)
        local index = math.random(3)
        local ret = net.request(self, 100, "legion_trial_select",
            {pos = pos, index = index})
        log("%s legion_buff pos=%d,sceneid=%d,current=%d,choosed=%d,e=%d",
            self.rname, pos, DATA.sceneid, DATA.current, DATA.choosed or -1,
            ret.e)
        return ret
    end,
    [objtype.transport] = function(self, pos)
        local ret =
            net.request(self, 100, "legion_trial_transport", {pos = pos})
        log("%s legion_transport pos=%d,sceneid=%d,current=%d,choosed=%d,e=%d",
            self.rname, pos, DATA.sceneid, DATA.current, DATA.choosed or -1,
            ret.e)
        return ret
    end
}

local function rand_pos()
    local sceneid, current = DATA.sceneid, DATA.current
    local objs = utable.getsub(DATA, "objs")
    local r = {}
    local pos
    local poscfg = CFG_POS[sceneid][current]
    for _, v in ipairs(poscfg.next or {}) do
        local p = v[1]
        if objs[p] then
            table.insert(r, v[1])
            if p == current then pos = p end
        end
    end
    for _, v in ipairs(poscfg.new or {}) do
        local p = v[1]
        if objs[p] then
            table.insert(r, v[1])
            if p == current then pos = p end
        end
    end
    local s = table.concat(r, ",")
    pos = pos or r[math.random(#r)]
    log("rand_pos pos=%d from %s", pos or -1, s)
    return pos
end

local function loop(self)
    while true do
        skynet.sleep(100)
        local pos = rand_pos()
        log("legion_trial loop pos=%s", pos or "")
        if not pos then
            log("%s legion_finish sceneid=%d,current=%d", self.rname,
                DATA.sceneid, DATA.current)
            return true
        end
        local obj = DATA.objs[pos]
        local objcfg = CFG_OBJ[obj.objid]
        local f = action[objcfg.type]
        local ret = f(self, pos, objcfg.para)
        if ret.e ~= 0 then
            log("%s legion loop return sceneid=%d,current=%d,e=%d", self.rname,
                DATA.sceneid, DATA.current, ret.e)
            return false
        end
    end
end

function _H.legion_trial_scene(self, msg)
    DATA = msg
    self.__legion__scene__ = {}
end

function _H.legion_trial_objs(self, msg)
    -- pdump(msg.objs, "objs")
    local objs = utable.getsub(DATA, "objs")
    for uuid, obj in pairs(msg.objs) do
        local pos = obj.pos
        objs[pos] = obj
    end
end

function _H.legion_trial_heroes(self, msg)
    local heroes = utable.getsub(DATA, "heroes")
    for uuid, hero in pairs(msg.heroes) do heroes[uuid] = hero end
end

function _H.legion_trial_move(self, msg)
    log("%s legion_trial_move %d", self.rname, msg.current)
    DATA.current = msg.current
    DATA.choosed = nil
end

function _H.legion_trial_del(self, msg)
    local s = table.concat(msg.objs, ',')
    log("%s legion_trial_del %s", self.rname, s)
    local objs = utable.getsub(DATA, "objs")
    for _, pos in pairs(msg.objs) do
        assert(objs[pos])
        objs[pos] = nil
    end
end

function _H.legion_trial_battleend(self, msg)
    log("battle_end win=%d", msg.endinfo.win)
    return battle.over(self, true, msg)
end

local function start(self)
    local ret = net.request(self, 100, "legion_trial_start")
    if ret.e ~= 0 then return end
    log("%s legion_start e=%d", self.rname, ret.e)
    loop(self)
end

function _M.onlogin(self)
    chat(self, "lua@robot_legion_trial_reset()")
    log("onlogin legion_trial fnopen=%s", tostring(fnopen.check(self, NM)))
    if fnopen.check(self, NM) then start(self) end
end

return _M
