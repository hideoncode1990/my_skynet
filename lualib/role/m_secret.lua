local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local map = require "role.map"
local task = require "task"
local client = require "client.mods"
local LOCK = require("skynet.queue")()
local m_battle = require "role.m_battle"
local _H = require "handler.client"
local explore = require "role.m_explore"
local fnopen = require "role.fnopen"
local flowlog = require "flowlog"
local event_listen = require "event_listen.helper"
local utime = require "util.time"
local hinit = require "hero"

local NM<const> = "secret"

local CFG
skynet.init(function()
    CFG = cfgproxy("secretstory")
end)

local cache = require("mongo.role")("secret")
local schema = require "mongo.schema"
cache.schema(schema.OBJ {
    current = schema.ORI,
    boxinfo = schema.NOBJ(schema.OBJ {
        boxlist = schema.NOBJ(schema.OBJ {
            uuid = schema.ORI,
            box = schema.ORI,
            id = schema.ORI
        }),
        finish = schema.ORI
    }),
    start_ti = schema.ORI
})

local function enter_push(self)
    local C = cache.get(self)
    local boxinfo = {}
    for id, v in pairs(C.boxinfo or {}) do
        boxinfo[id] = {id = id, boxlist = v.boxlist}
    end
    client.enter(self, NM, "secret_info",
        {current = C.current, boxinfo = boxinfo})
end

require("role.mods") {
    name = NM,
    enter = function(self)
        if fnopen.check_open(self, NM) then enter_push(self) end
    end
}

local function get_boxinfo(self, id)
    local boxinfo = cache.getsub(self, "boxinfo", id)
    local boxlist = boxinfo.boxlist
    if not boxlist then
        boxlist = {}
        boxinfo.boxlist = boxlist
    end
    if not boxinfo.boxcnt then
        local cnt = 0
        for _ in pairs(boxlist) do cnt = cnt + 1 end
        boxinfo.boxcnt = cnt
    end
    return boxinfo, boxlist
end

local function calc_box_progress(self, id)
    return get_boxinfo(self, id).boxcnt / CFG[id].target_sum
end

local check_fn = {
    [1] = function(self, mainline)
        return self.mainline >= mainline
    end,
    [2] = function(self, id, progress)
        return calc_box_progress(self, id) >= progress / 100
    end
}

local function enter_check(self, condition)
    for _, v in ipairs(condition) do
        local fn = check_fn[v[1]]
        if not fn(self, table.unpack(v, 2)) then return false end
    end
    return true
end

local function rate_log(self, id)
    local progress = calc_box_progress(self, id)
    flowlog.role(self, NM, {id = id, progress = math.floor(progress * 100)})
end

function _H.secret_start(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local id = msg.id
    local cfg = assert(CFG[id])
    local boxinfo, boxlist = get_boxinfo(self, id)
    if not enter_check(self, cfg.condition) then return {e = 2} end

    local C = cache.get(self)
    local ctx = {
        rid = self.rid,
        owner = NM .. self.rid,
        mainline = self.mainline,
        boxlist = boxlist,
        new = not (C.current == id),
        average_st = hinit.stage_top5_average(self),
        battle_mapid = cfg.battle,
        mod_nm = NM,
        mapid = cfg.mapid
    }
    local cb = function(addr)
        local sb_box_open = event_listen.subscribe(addr, "box_open",
            function(ret)
                boxlist[ret.uuid] = ret
                cache.dirty(self)
                boxinfo.boxcnt = boxinfo.boxcnt + 1
                client.push(self, NM, "secret_box_open",
                    {current = id, the_box = ret})

                rate_log(self, id)

                local finish = boxinfo.finish
                if not finish then
                    local done = true
                    for uuid in pairs(cfg.target1) do
                        if not boxlist[uuid] then
                            done = nil
                            break
                        end
                    end
                    if done then
                        boxinfo.finish = true
                        cache.dirty(self)
                        task.trigger(self, "secret_finish")
                    end
                end
            end)
    end
    LOCK(explore.start, self, ctx, cb)
    C.current = id
    C.start_ti = utime.time_int()
    cache.dirty(self)

    return {e = 0}
end

function _H.secret_over(self)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    LOCK(explore.over, self)
    local C = cache.get(self)
    C.current = nil
    cache.dirty(self)
    return {e = 0}
end

--[[
    100场景地址不存在
    101.场景玩家不在怪物点旁 102.怪物已死亡
    103.阵容中有不存在的英雄 104.阵容中有相同tab的英雄
    105.阵容中有死亡英雄 106.正在进行一场战斗
    107.补给值不足(裂隙功能才有) 108.超过阵容数量上限
    109.倍速功能未开放
    110.队伍没有英雄
    111.队伍不该有真实英雄(即包包里面的英雄)
--]]
function _H.secret_battle_start(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local bi = msg.battle_info

    local list, list_save = m_battle.check_bi(self, bi, true)
    if not list then return {e = list_save} end

    local ok, err = map.battle_start(self, msg.uuid, list, bi)
    if not ok then return {e = err} end

    m_battle.set_lineup(self, NM, list_save)
    return {e = 0}
end

skynet.init(function()
    CFG = cfgproxy("secretstory")
    fnopen.reg(NM, NM, function(self)
        enter_push(self)
    end)
end)
