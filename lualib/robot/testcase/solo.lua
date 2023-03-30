local skynet = require "skynet"
local net = require "robot.net"
local fnopen = require "robot.fnopen"
local herobag = require "robot.herobag"
local battle = require "robot.battle"
local fight_lock = require "robot.fight_lock"
local log = require "robot.log"

local _H = require "handler.client"

require "util"

local NM<const> = "solo"

function _H.solo_result(self, msg)
    return battle.over(self, true, msg)
end

function _H.solo_add_record(self, msg)
    -- pdump(msg, "solo_add_record" .. self.rid)
end

local function solo_info(self)
    local ret = net.request(self, nil, "solo_info")
    local e = ret and ret.e
    log(self, {opt = "solo_info", e = e or false})
    -- pdump(ret, "solo_info_" .. self.rid)
    return e == 0
end

local records
local function solo_records(self)
    local ret = net.request(self, nil, "solo_records")
    local e = ret and ret.e
    log(self, {opt = "solo_records", e = e or false})
    if e == 0 then
        records = ret.records
        return true, records
    else
        return false
    end
end

local function solo_query_defend(self)
    local ret = net.request(self, nil, "solo_query_defend", {})
    local e = ret and ret.e
    log(self, {opt = "solo_query_defend", e = e or false})
    -- pdump(ret.list, "solo_query_defend" .. self.rid)
    return e == 0
end

local function solo_range(self)
    local ret = net.request(self, nil, "solo_range", {})
    local e = ret and ret.e
    log(self, {opt = "solo_range", e = e or false})
    return e == 0
end

local matchlist
local function solo_match(self)
    local ret = net.request(self, nil, "solo_match")
    local e = ret and ret.e
    log(self, {opt = "arena_match", e = e or false})

    local successful = e == 0
    if successful then matchlist = ret.list end
    return successful
end

local function solo_set_defend(self, msg)
    local ret = net.request(self, nil, "solo_set_defend", msg)
    -- pdump(ret, "solo_set_defend" .. self.rid)
end

local function solo_battle_fight(self, msg)
    local ret = net.request(self, 100, "solo_battle_fight", msg)
    local e = ret.e
    if e == 0 then
        return battle.wait(self, {nm = NM})
    else
        return false, e
    end
end

local function try_inner(self)
    if not (solo_info(self) and solo_query_defend(self) and solo_range(self) and
        solo_records(self) and solo_match(self)) then

        matchlist = nil
        records = nil

        return false, 1
    end

    local size = #matchlist
    if size <= 0 then return false, 2 end

    local enemy = matchlist[math.random(1, size)]

    -- pdump(enemy, "solo_enemy")

    local lineup = herobag.generate_solo_lineup(self)
    if not lineup then return false, 4 end
    -- pdump(lineup, "solo_lineup")

    local msg = {
        rid = enemy.rid,
        battle_info = {
            list = lineup,
            auto = true,
            save = true,
            multi_speed = battle.get_accelerate(self)
        }
    }
    return solo_battle_fight(self, msg)
end

local function do_solo(self)
    local ok, err = fight_lock(try_inner, self)
    if ok then
        print("try_solo_successfully")
        skynet.sleep(3 * 100)
    else
        print("try_solo_failed err:", err)
    end
end

return {
    onlogin = function(self)
        if fnopen.check(self, NM) then do_solo(self) end
    end
}
