local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local map = require "role.map"
local task = require "task"
local client = require "client.mods"
local LOCK = require("skynet.queue")()
local m_battle = require "role.m_battle"
local _H = require "handler.client"
local explore = require "role.m_explore"
local flowlog = require "flowlog"
local event_listen = require "event_listen.helper"
local utime = require "util.time"
local hinit = require "hero"
local timer = require "timer"

local NM<const> = "secretact"

local CFG, TIMER
skynet.init(function()
    CFG = cfgproxy("secretact")
end)

local cache = require("mongo.role")("secretact")
local schema = require "mongo.schema"
cache.schema(schema.OBJ {
    current = schema.ORI,
    boxinfo = schema.NOBJ(schema.OBJ {
        boxlist = schema.NOBJ(schema.OBJ {
            uuid = schema.ORI,
            box = schema.ORI,
            id = schema.ORI
        }),
        finish = schema.ORI,
        new = schema.ORI
    }),
    start_ti = schema.ORI
})

local function generate_owner(self, id)
    return NM .. self.rid .. id
end

-- 约定：boxinfo[id]存在，则该id 的场景数据一定存在，
-- 需要根据该id的配置是否过期 决定是否删除map里面的数据

require("role.mods") {
    name = NM,
    load = function(self)
        local C = cache.get(self)
        local boxinfo = C.boxinfo
        if not boxinfo then return end

        local now = utime.time_int()
        local list = {}
        for id in pairs(boxinfo) do
            local cfg = CFG[id]

            if not cfg or now < cfg.startti or now >= cfg.overti then
                boxinfo[id] = nil
                table.insert(list, generate_owner(self, id))
            end
        end
        if next(list) then
            cache.dirty(self)
            explore.deldata(list) -- 过期地图数据删除
        end
    end,
    enter = function(self)
        local C = cache.get(self)
        local boxinfo = {}
        for id, v in pairs(C.boxinfo or {}) do
            boxinfo[id] = {id = id, boxlist = v.boxlist}
        end
        client.enter(self, NM, "secretact_info", {boxinfo = boxinfo})
    end,
    unload = function(self)
        if TIMER then timer.del(TIMER.id) end
    end
}

local function get_boxinfo(self, id)
    local infos = cache.getsub(self, "boxinfo")
    local boxinfo = infos[id]

    local first
    if not boxinfo then
        boxinfo = {}
        first = true
    end
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
    return boxinfo, boxlist, first
end

local function calc_box_progress(self, id)
    return get_boxinfo(self, id).boxcnt / CFG[id].target_sum
end

local function rate_log(self, id)
    local progress = calc_box_progress(self, id)
    flowlog.role(self, NM, {id = id, progress = math.floor(progress * 100)})
end

local function over(self, id, now)
    LOCK(explore.over, self)
    cache.dirty(self)
end

function _H.secretact_start(self, msg)
    local id = msg.id
    local cfg = CFG[id]
    if not cfg then return {e = 2} end

    local now = utime.time_int()
    if now < cfg.startti or now >= cfg.overti then return {e = 3} end

    local C = cache.get(self)
    local boxinfo, boxlist, first = get_boxinfo(self, id)
    local owner = generate_owner(self, id)

    local ctx = {
        rid = self.rid,
        owner = owner,
        mainline = self.mainline,
        boxlist = boxlist,
        new = boxinfo.new,
        average_st = hinit.stage_top5_average(self),
        battle_mapid = cfg.battle,
        mod_nm = NM,
        mapid = cfg.mapid,
        hero_mode = cfg.type,
        para = cfg.para
    }
    local cb = function(addr)
        local sb_box_open = event_listen.subscribe(addr, "box_open",
            function(ret)
                boxlist[ret.uuid] = ret
                cache.dirty(self)
                boxinfo.boxcnt = boxinfo.boxcnt + 1
                client.push(self, NM, "secretact_box_open",
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
                        task.trigger(self, "secretact_finish")
                    end
                end
            end)
    end

    LOCK(explore.start, self, ctx, cb)

    if first then C.boxinfo[id] = boxinfo end
    if boxinfo.new then boxinfo.new = nil end

    C.start_ti = utime.time_int()
    cache.dirty(self)

    if TIMER and TIMER.owner ~= owner then
        timer.del(TIMER.id)
        TIMER = nil
    end
    if not TIMER then
        TIMER = {
            id = timer.add((cfg.overti - now) * 100, function()
                TIMER = nil
                over(self, id, now)
            end),
            owner = owner
        }
    end
    return {e = 0}
end

function _H.secretact_over(self, msg)
    local id = msg.id
    local cfg = CFG[id]
    if not cfg then return {e = 2} end

    local now = utime.time_int()
    if now < cfg.startti or now >= cfg.overti then return {e = 3} end

    local boxinfo = cache.getsub(self, "boxinfo")[id]
    if not boxinfo then return {e = 4} end

    over(self, id, now)
    boxinfo.new = 1 -- 下次开启刷新数据
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
--]]
function _H.secretact_battle_start(self, msg)
    local bi = msg.battle_info
    local list, list_save = m_battle.check_bi(self, bi, true)
    if not list then return {e = list_save} end

    local ok, err = map.battle_start(self, msg.uuid, list, bi)
    if not ok then return {e = err} end

    m_battle.set_lineup(self, NM, list_save)
    return {e = 0}
end
