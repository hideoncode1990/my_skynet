local skynet = require "skynet"
local client = require "client"
local cfgproxy = require "cfg.proxy"
local hinit = require "hero"
local uaward = require "util.award"
local hattrs = require "hero.attrs"
local fnopen = require "role.fnopen"
local roleinfo = require "roleinfo"
local roleinfo_change = require "roleinfo.change"
local award = require "role.award"
local m_battle = require "role.m_battle"
local zset = require "zset"
local event = require "role.event"
local utime = require "util.time"
local uniq = require "uniq.c"
local task = require "task"
local m_report = require "role.m_report"
local cache = require("mongo.role")("solo")
local schema = require "mongo.schema"
local flowlog = require "flowlog"
local addition = require "role.addition"
local lang = require "lang"

local _H = require "handler.client"
local _LUA = require "handler.lua"

local insert = table.insert

local NM<const> = "solo"

local day_sec = 86400

cache.schema(schema.OBJ {
    update = schema.ORI,
    times_used = schema.ORI,
    defend = schema.MAPF("uuid")
})

local CFG, CFG_ROBOT, BASIC
local solod, solo_record, zsetrank

local query_defend
skynet.init(function()
    CFG, CFG_ROBOT, BASIC = cfgproxy("solo", "solo_robot", "basic")
    solod = skynet.uniqueservice("game/solod")
    solo_record = skynet.uniqueservice("game/solo_record")
    zsetrank = skynet.uniqueservice("base/zsetrank")
    fnopen.reg(NM, NM, function(self)
        skynet.call(solod, "lua", "solo_info", self.rid)
        query_defend(self)
    end)
end)

local function change_to_roleinfo(self, lineup, zdl)
    roleinfo_change.change(self, "solo_defend_lineup", lineup)
    roleinfo_change.change(self, "solo_defend_zdl", zdl)
end

local function generate_defend(self, C)
    local arr = hinit.besthero_in_different_tab(self)
    local lineup, lineup_dict, zdl_sum = {}, {}, 0
    for i = 1, BASIC.battlemax do
        if arr[i] then
            local info = arr[i]
            local uuid, zdl = info.uuid, info.zdl
            local hero = hinit.query(self, info.uuid)
            insert(lineup,
                {uuid = uuid, pos = i, id = hero.id, level = hero.level})
            lineup_dict[uuid] = {uuid = uuid, pos = i}
            zdl_sum = zdl_sum + zdl
        else
            break
        end
    end
    assert(#lineup > 0)
    C.defend = lineup_dict
    cache.dirty(self)
    change_to_roleinfo(self, lineup, zdl_sum)
    return lineup_dict
end

local function calc_defend_lineup(self, c)
    local defend_lineup, zdl_sum = {}, 0
    for uuid, v in pairs(c) do
        local hero = assert(hinit.query(self, uuid))
        insert(defend_lineup,
            {uuid = uuid, pos = v.pos, id = hero.id, level = hero.level})
        local _, zdl = hattrs.query(self, uuid)
        zdl_sum = zdl_sum + zdl
    end
    change_to_roleinfo(self, defend_lineup, zdl_sum)
end

query_defend = function(self)
    local C = cache.get(self)
    if not C.defend then
        return generate_defend(self, C)
    else
        local ret, defend_lineup, zdl_sum, change = {}, {}, 0, nil
        for uuid, v in pairs(C.defend) do
            local hero = hinit.query(self, uuid)
            if hero then
                ret[uuid] = {uuid = uuid, pos = v.pos}
                insert(defend_lineup, {
                    uuid = uuid,
                    pos = v.pos,
                    id = hero.id,
                    level = hero.level
                })
                local _, zdl = hattrs.query(self, uuid)
                zdl_sum = zdl_sum + zdl
            else
                change = true
            end
        end
        if not next(ret) then
            generate_defend(self, C)
        elseif change then
            C.defend = ret
            cache.dirty(self)
            change_to_roleinfo(self, defend_lineup, zdl_sum)
        end
    end
    return C.defend
end

require("role.mods") {
    name = NM,
    loaded = function(self)
        if fnopen.check_open(self, NM) then query_defend(self) end
    end
}

local function calc_season(time)
    return (time - CFG.season_starttime) // (CFG.season * day_sec)
end

local function same_season(time1, time2)
    return calc_season(time1) == calc_season(time2)
end

local function calc_season_overtime(time)
    local n = calc_season(time)
    return CFG.season_starttime + (n + 1) * (CFG.season * day_sec) - time
end

local function calc_offset(time)
    return time - utime.begin_day(time)
end

local function calc_daily_overtime(time)
    local update_time = utime.begin_day(time) +
                            calc_offset(CFG.season_starttime)
    local overtime = update_time - time
    return overtime >= 0 and overtime or (day_sec + overtime)
end

function _LUA.solo_add_record(self, record, point_new)
    skynet.call(solo_record, "lua", "add", self.rid, record)
    task.trigger(self, "solo_score", point_new)
end

function _LUA.solo_create_as_enemy(self)
    local list = {}
    for _, v in pairs(cache.getsub(self, "defend")) do insert(list, v) end
    list = m_battle.check_lineup(self, list)
    return m_battle.create_heroes(self, list), self.rname, self.head, self.level
end

local function self_defend_zdl(self)
    local C = cache.get(self)
    local sum = 0
    for uuid in pairs(C.defend) do
        local _, zdl = hattrs.query(self, uuid)
        sum = sum + zdl
    end
    return sum
end

local function free_times_used(self, now)
    local C = cache.get(self)
    if not utime.same_day(C.update or 0, now) then
        C.times_used = 0
        C.update = now
        cache.dirty(self)
    end
    return C.times_used or 0
end

function _H.solo_info(self)
    if not fnopen.check_open(self, NM) then return {e = 0} end
    local group = skynet.call(solod, "lua", "solo_info", self.rid)
    local rank, point = zset.rank(group, self.rid)
    local now = utime.time_int()
    return {
        e = 0,
        season_overtime = calc_season_overtime(now),
        daily_overtime = calc_daily_overtime(now),
        rank = rank,
        point = point or CFG.point,
        defend_zdl = self_defend_zdl(self),
        times_used = free_times_used(self, now),
        group = group
    }
end

function _H.solo_range(self)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local group = skynet.call(solod, "lua", "solo_info", self.rid)
    local data, rank, obj = skynet.call(zsetrank, "lua", "query_rank", self.rid,
        group, nil, {"solo_defend_zdl"})
    local point = obj and obj.value
    return {e = 0, rank = rank, point = point or CFG.point, data = data}
end

function _H.solo_query_defend(self)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    return {e = 0, list = query_defend(self)}
end

function _H.solo_set_defend(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local list = msg.list
    if not next(list) then return {e = 2} end

    local dict, tab, postab, cnt = {}, {}, {}, 0
    for _, v in pairs(list) do
        local hero = hinit.query(self, v.uuid)
        if not hero then
            return {e = 3}
        else
            local pos = v.pos
            if not pos or postab[pos] then return {e = 5} end
            postab[pos] = true

            local hero_cfg = hinit.query_cfg_byid(self, hero.id)
            local ttab = hero_cfg.tab
            if tab[ttab] then return {e = 4} end
            dict[v.uuid] = {uuid = v.uuid, pos = pos}
            tab[ttab] = true
            cnt = cnt + 1
        end
    end
    if cnt > BASIC.battlemax then return {e = 6} end

    cache.get(self).defend = dict
    cache.dirty(self)
    calc_defend_lineup(self, dict)
    return {e = 0}
end

function _H.solo_records(self)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    return {e = 0, records = skynet.call(solo_record, "lua", "get", self.rid)}
end

local LIST, ROBOTS
function _H.solo_match(self)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local ret = {}
    local list, listdict = skynet.call(solod, "lua", "solo_match", self.rid,
        self.mainline)
    -- 有listdict表示是和玩家匹配
    LIST, ROBOTS = nil, nil
    if listdict then
        LIST = {listdict = listdict, time = utime.time_int()}
        local success = roleinfo.query_list(listdict, {"solo_defend_zdl"})
        for _, rid in ipairs(list) do
            local info = success[rid]
            info.point = listdict[rid]
            insert(ret, info)
        end
    else
        ROBOTS = {}
        for _, id in ipairs(list) do
            local rid = uniq.id()
            local cfg = CFG_ROBOT[id]
            insert(ret, {
                rid = rid,
                rname = lang("SOLO_RNAME_" .. cfg.rname_id),
                level = cfg.level,
                point = cfg.point,
                solo_defend_zdl = cfg.zdl,
                head = (cfg.head[2] << 32) | cfg.head[1],
                monster = cfg.monster
            })
            ROBOTS[rid] = cfg.id
        end
    end
    return {e = 0, list = ret}
end

function _H.solo_detail(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end

    local info = roleinfo.query(msg.rid, {
        "solo_defend_lineup", "solo_defend_zdl", "signature"
    })
    return {e = 0, info = info}
end

local function check_cost(self, time)
    if not (free_times_used(self, time) < CFG.free + addition.sum(self, "solo")) then
        if not award.checkdel(self, {CFG.cost}) then return false end
    end
    return true
end

function _LUA.solo_check_cost(self, time, eid)
    local C = cache.get(self)
    if free_times_used(self, time) < CFG.free + addition.sum(self, "solo") then
        C.times_used = (C.times_used or 0) + 1
        cache.dirty(self)
        return true
    else
        return award.del(self, {
            flag = "solo_battle_fight",
            arg1 = self.rid,
            arg2 = eid
        }, {CFG.cost})
    end
end

local lock = require("skynet.queue")()

local function deal_with_rank(rid, win, ranktp, change)
    local _, point = zset.rank(ranktp, rid)
    if win == 1 then
        point = point + change
    else
        point = math.max((point - change), 0)
    end
    zset.set(ranktp, {id = rid, value = point})
    return zset.rank(ranktp, rid)
end

function _LUA.solo_battle_result(self, win, ranktp, obj, eobj, reward, endinfo)
    local change = obj.change
    local rid = self.rid
    local _, point = zset.rank(ranktp, rid)
    point = point or CFG.point
    if win == 1 then
        point = point + change
    else
        point = math.max((point - change), 0)
    end
    zset.set(ranktp, {id = rid, value = point})
    local rank_new, point_new = lock(deal_with_rank, rid, win, ranktp, change)
    task.trigger(self, "solo_score", point_new)
    if not eobj then return rank_new, point_new end

    obj.rank_new = rank_new
    obj.point_new = point_new
    task.trigger(self, "fight")
    if win == 1 then
        task.trigger(self, "fight_win")
        award.adde(self, {
            flag = "solo_result",
            theme = "SOLO_REWARD_FULL_THEME_",
            content = "SOLO_REWARD_FULL_CONTENT_"
        }, reward)
    end
    client.push(self, "solo_result", {
        win = win,
        left = obj,
        right = eobj,
        reward = uaward.pack(reward or {}),
        endinfo = endinfo
    })

    flowlog.role(self, NM, {
        flag = "battle_result",
        win = win,
        lpoint = obj.point,
        lpoint_new = obj.point_new,
        rpoint = eobj.point,
        rpoint_new = eobj.point_new
    })
    return rank_new, point_new
end

function _H.solo_battle_fight(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local rid, bi, by_record = msg.rid, msg.battle_info, msg.by_record

    local right, robot_id
    local enemy = {rid = rid}
    local startti = utime.time_int()
    if ROBOTS then -- 如果打机器人
        robot_id = ROBOTS[rid]
        if not robot_id then return {e = 2} end

        local cfg = CFG_ROBOT[robot_id]
        right = m_battle.create_monsters(cfg.monster)
        local player = right.player
        player.bossid = nil
        local rname = lang("SOLO_RNAME_" .. cfg.rname_id)
        local level = cfg.level

        player.level = level
        player.rname = rname

        enemy.robot_id = robot_id
        enemy.point = cfg.point
        enemy.rname = rname
        enemy.level = level
        enemy.head = (cfg.head[2] << 32) | cfg.head[1]
    else -- 如果打真人
        if by_record then -- 如果是通过记录申请战斗
            local record = skynet.call(solo_record, "lua", "find_record",
                self.rid, by_record)
            if not record then return {e = 3} end
            if record.used == 1 then return {e = 4} end
        else -- 如果是通过匹配申请的战斗
            local listdict, time = LIST.listdict, LIST.time
            if not same_season(time, startti + CFG.settle_cd) then
                LIST = nil
                return {e = 6}
            end
            if not listdict[rid] then return {e = 8} end
        end
        if not check_cost(self, startti) then return {e = 7} end
    end

    local list, list_save = m_battle.check_bi(self, bi)
    if not list then return {e = list_save} end

    local left, err = m_battle.create_heroes(self, list)
    if not left then return {e = err} end

    local obj = {
        rid = self.rid,
        rname = self.rname,
        level = self.level,
        head = self.head,
        addr = self.addr,
        fd = self.fd
    }

    local ok, e = skynet.call(solod, "lua", "solo_battle_fight", obj, enemy,
        left, right, bi, startti, by_record)
    if not ok then return {e = e} end

    LIST = nil
    ROBOTS = nil
    m_battle.set_lineup(self, NM, list_save)
    flowlog.role(self, NM, {flag = "battle_fight", rrid = rid, robot = robot_id})
    return {e = 0, times_used = cache.get(self).times_used}
end

m_report.reg(NM, function(self, key)
    return skynet.call(solo_record, "lua", "find_report", self.rid, key)
end)

event.reg("EV_HERO_STAGEUP", NM, function(self, uuid2id)
    local c = cache.getsub(self, "defend")
    local change
    for uuid in pairs(uuid2id) do
        if c[uuid] then
            change = true
            break
        end
    end
    if change then calc_defend_lineup(self, c) end
end)

event.reg("EV_HERO_DELS", NM, function(self, uuids)
    local c = cache.getsub(self, "defend")
    local change
    for _, uuid in ipairs(uuids) do
        if c[uuid] then
            change = true
            c[uuid] = nil
        end
    end
    if change then
        cache.dirty(self)
        if next(c) then
            calc_defend_lineup(self, c)
        else
            generate_defend(self, cache.get(self))
        end
    end
end)

event.reg("EV_HERO_ATTRS_CHANGE", NM, function(self, change)
    local c = cache.getsub(self, "defend")
    for uuid in pairs(change) do
        if c[uuid] then
            calc_defend_lineup(self, cache.getsub(self, "defend"))
            break
        end
    end
end)
