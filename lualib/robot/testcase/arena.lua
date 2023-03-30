local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"

local net = require "robot.net"
local _H = require "handler.client"
local log = require "robot.log"
local fnopen = require "robot.fnopen"
local herobag = require "robot.herobag"
local battle = require "robot.battle"
local logerr = require "log.err"
local fight_lock = require "robot.fight_lock"

local NM<const> = "arena"

local INFO, CFG = {}

skynet.init(function()
    CFG = cfgproxy("arena")
end)

function _H.arena_result(self, msg)
    if msg.record then return battle.over(self, true, msg) end
end

local function arena_info(self)
    local ret = net.request(self, 100, "arena_info")
    local e = ret and ret.e
    log(self, {opt = "arena_info", e = e or false})
    -- pdump(ret, "arena_info")

    local successful = e == 0
    if successful then
        INFO.stage = ret.stage
        INFO.rank = ret.rank
        INFO.times_used = ret.times_used
        INFO.self_defend_zdl = ret.self_defend_zdl
        INFO.coin = ret.coin
    end
    return successful
end

local function arena_query_defend(self)
    local ret = net.request(self, 100, "arena_query_defend")
    local e = ret and ret.e
    log(self, {opt = "arena_query_defend", e = e or false})
    -- pdump(ret, "arena_query_defend")

    local successful = e == 0
    if successful then INFO.defend = ret.ret end
    return successful
end

local rangelist
local function arena_range(self)
    local ret = net.request(self, 100, "arena_range")
    local e = ret and ret.e
    log(self, {opt = "arena_range", e = e or false})
    -- pdump(ret, "arena_range")

    local successful = e == 0
    if successful then
        INFO.coin = ret.coin
        INFO.self = ret.self
        rangelist = ret.list
    end
    return successful
end

local matchlist
local function arena_match(self)
    local ret = net.request(self, 100, "arena_match")
    local e = ret and ret.e
    log(self, {opt = "arena_match", e = e or false})
    -- pdump(ret, "arena_match")

    local successful = e == 0
    if successful then matchlist = ret.list end
    return successful
end

local function arena_detail(self, msg)
    local ret = net.request(self, 100, "arena_detail", msg)
    local e = ret and ret.e
    log(self, {opt = "arena_detail", e = e or false})
    -- pdump(ret, "arena_detail")

    if e == 0 then
        return true, ret.info
    else
        return false
    end
end

-- 暂时不测试 设置防守阵容接口
-- local function arena_set_defend(self,msg)
-- end

local records
local function arena_records(self)
    local ret = net.request(self, 100, "arena_records")
    local e = ret and ret.e
    log(self, {opt = "arena_records", e = e or false})
    -- pdump(ret, "arena_records")

    if e == 0 then
        records = ret.records
        return true, records
    else
        return false
    end
end

local function arena_battle_fight(self, msg)
    local ret = net.request(self, 300, "arena_battle_fight", msg)
    local e = ret.e
    if e == 0 then
        -- 3v3是快速战斗，需要skip字段 免发battle_real_start
        return battle.wait(self, {nm = NM, skip = true})
    else
        return false, e or 9009
    end
end

local function try_inner(self)
    if not arena_info(self) then return false, 9001 end
    if not arena_query_defend(self) then return false, 9002 end
    if not arena_range(self) then
        rangelist = nil
        return false, 9003
    end

    if not arena_records(self) then
        records = nil
        return false, 9005
    end

    if not arena_match(self) then
        matchlist = nil
        return false, 9004
    end

    local size = #matchlist
    if size <= 0 then return false, 9006 end

    local enemy = matchlist[math.random(1, size)]
    -- pdump(enemy, "enemy")

    local ok, detail = arena_detail(self, {rid = enemy.rid})
    if not ok then return false, 9007 end
    -- pdump(detail, "detail")

    local lineup = herobag.generate_arena_lineup(self)
    if not lineup then return false, 9008 end
    -- pdump(lineup, "lineup")

    local msg = {
        rid = enemy.rid,
        battle_info = {
            multi_list = lineup,
            auto = true,
            multi_speed = battle.get_accelerate(self)
        }
    }
    return arena_battle_fight(self, msg)
end

local function do_arena(self)
    local ok, _ok, err = pcall(fight_lock, try_inner, self)
    if not ok then
        logerr(_ok)
    else
        if _ok then
            print("try_arena_win!!!", self.rname, self.rid)
            skynet.sleep(10 * 100)
        else
            print("try_arena_failed", self.rname, self.rid, err)
            skynet.sleep(CFG.cd_time * 100)
        end
    end
end

return {
    onlogin = function(self)
        if fnopen.check(self, NM) then do_arena(self) end
    end
}
