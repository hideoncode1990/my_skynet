local skynet = require "skynet"
local net = require "robot.net"
local _H = require "handler.client"
local fnopen = require "robot.fnopen"
local herobag = require "robot.herobag"
local battle = require "robot.battle"
local log = require "log"
local chat = require "robot.chat"

local NM<const> = "guild_boss"
local C
local _M = {}

function _H.guild_info(self, msg)
    self.gid = msg.info.gid
    self.guild_contribution = msg.info.contribution
end

function _H.guild_boss_infos(self, msg)
    C = msg.infos
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

local function mopup(self, bossid)
    local ret = net.request(self, 100, "guild_boss_mopup", {id = bossid})
    log("%s guild_boss_mopup [%d] e= %d", self.rname, bossid, ret.e)
end

local function loop(self, bossid)
    log("%s guild boss loop %d", self.rname, bossid)
    if self.pos == 3 or self.pos == 2 then
        local ret = net.request(self, 100, "guild_boss_open", {id = bossid})
        log("%s guild_boss_open [%d] e= %d", self.rname, bossid, ret.e)
    end

    if math.random() < 0.5 then return mopup(self, bossid) end

    local battle_info = {
        list = get_lineup(self),
        auto = true,
        skip = true,
        multi_speed = battle.get_accelerate(self)
    }
    local ret = net.request(self, 100, "guild_boss_fight",
        {id = bossid, battle_info = battle_info})
    if ret.e == 0 then return battle.wait(self, {nm = NM}) end
end

local function work(self)
    for bossid, data in pairs(C) do
        for _ = data.times, 3 do loop(self, bossid) end
    end
end

function _H.guild_boss_result(self, msg)
    log("%s battle_end win=%d", self.rname, msg.endinfo.win)
    return battle.over(self, true, msg)
end

function _M.onlogin(self)
    if fnopen.check(self, NM) then
        if self.gid then
            if self.guild_contribution or 0 < 100000 then
                chat(self, "lua@guild(10000)")
            end
            work(self)
        end
    end
end

return _M
