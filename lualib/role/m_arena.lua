local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local hinit = require "hero"
local hattrs = require "hero.attrs"
local fnopen = require "role.fnopen"
local roleinfo = require "roleinfo.change"
local award = require "role.award"
local m_battle = require "role.m_battle"
local battle = require "battle"
local event = require "role.event"
local utime = require "util.time"
local agent = require "role.agent"
local task = require "task"
local client = require "client"
local m_report = require "role.m_report"
local cache = require("mongo.role")("arena_new")
local schema = require "mongo.schema"
local flowlog = require "flowlog"
local logerr = require "log.err"
local utable = require "util.table"
local awardtype = require "role.award.type"

local _H = require "handler.client"
local _LUA = require "handler.lua"

local insert = table.insert

local ARENA<const> = "arena"
local TEAM<const> = 3
local DAYSEC<const> = 86400

local CFG, CFG_RANK, CFG_STAGE, BASIC, CFG_MONEY
local arenad, arena_record

cache.schema(schema.OBJ {
    update = schema.ORI,
    coin = schema.ORI,
    times_used = schema.ORI,
    times_update = schema.ORI,
    rank = schema.ORI,
    stage = schema.ORI,
    defends = schema.ARR(schema.ARR(schema.OBJ {
        uuid = schema.ORI,
        pos = schema.ORI
    }))

})

-- c 是defends 或者是 lineup，它们必须结构相同
local function foreach(_, c, cb)
    for i, list in ipairs(c) do
        for _, v in ipairs(list) do
            local ret = cb(i, v.uuid, v)
            if ret then return ret end
        end
    end
end

local function calc_season(time)
    return (time - CFG.season_starttime) // (CFG.season * DAYSEC)
end

-- 所在赛季的开始时间点
local function calc_begin(_, time)
    return CFG.season_starttime + calc_season(time) * CFG.season * DAYSEC
end

-- 所在赛季的结束时间点
local function calc_over(_, time)
    return CFG.season_starttime + (calc_season(time) + 1) * CFG.season * DAYSEC
end

local function same_season(time1, time2)
    return calc_season(time1) == calc_season(time2)
end

local function calc_season_overtime(time)
    local n = calc_season(time)
    return CFG.season_starttime + (n + 1) * (CFG.season * DAYSEC) - time
end

local function coin_speed(_, stage, rank)
    return rank and CFG_RANK[rank].arena_coin or CFG_STAGE[stage].arena_coin
end

local function score_speed(_, stage, rank)
    return rank and CFG_RANK[rank].integral or CFG_STAGE[stage].integral
end

local function update_speed(self, stage, rank)
    roleinfo.changetable(self, {
        arena_coin_speed = coin_speed(self, stage, rank),
        arena_score_speed = score_speed(self, stage, rank)
    })
end

local function arena_reg(self)
    local C = cache.get(self)
    local now = utime.time_int()
    C.update = now

    local stage, rank = skynet.call(arenad, "lua", "arena_reg", self.rid)
    C.stage = stage
    C.rank = rank
    cache.dirty(self)
    update_speed(self, stage, rank)
    return stage, rank
end

local function calc_coin_inner(self, C, speed, begintime, overtime)
    local coin = C.coin or 0
    if coin < CFG.arena_coin_save then
        local get = math.floor((overtime - begintime) / 3600 * speed)
        C.coin = math.min(CFG.arena_coin_save, coin + get)
    end
    C.update = overtime
    cache.dirty(self)
    return C.coin
end

local function calc_coin(self, C, now)
    return calc_coin_inner(self, C, coin_speed(self, C.stage, C.rank), C.update,
        now)
end
-- 不同赛季
local function calc_coin_different_season(self, C, now_stage, now_rank)
    -- C.update时间点所在赛季的结算
    local seasonover = calc_over(self, C.update)
    calc_coin_inner(self, C, coin_speed(self, C.stage, C.rank), C.update,
        seasonover)
    -- 中间赛季
    local now = utime.time_int()
    local thisbegin = calc_begin(self, now)
    if thisbegin > seasonover then
        calc_coin_inner(self, C, coin_speed(self, C.stage, nil), seasonover,
            thisbegin)
    end
    -- 本赛季
    calc_coin_inner(self, C, coin_speed(self, now_stage, now_rank), thisbegin,
        now)
    update_speed(self, now_stage, now_stage)
end

-- 每个agent在load环节调用，对C.update,C.stage和C.rank校核，不同届的结算
local function check_season(self)
    local C = cache.get(self)
    local now = utime.time_int()
    local update = C.update

    if not update then
        arena_reg(self)
        update = C.update
        logerr("arena_update not exist")
    end

    local stage, rank = skynet.call(arenad, "lua", "arena_info", self.rid)
    if not stage then
        logerr("arena stage is wrong, need rereg. rid:%s ", self.rid)
        stage, rank = arena_reg(self)
    end

    if same_season(update, now) then
        if stage ~= C.stage or rank ~= C.rank then
            logerr("arena stage or rank wrong")
            C.stage = stage
            C.rank = rank
            cache.dirty(self)
        end
    else
        calc_coin_different_season(self, C, stage, rank)
        C.stage = stage
        C.rank = rank
        cache.dirty(self)
    end
end

local function calc_full_time(self, C, now, new_stage, new_rank)
    local coin = calc_coin(self, C, now)
    local stage, rank = C.stage, C.rank
    -- 如果new_stage存在，speed为新速率，否则为旧速率
    if new_stage then
        stage = new_stage
        rank = new_rank
    end
    local speed = coin_speed(self, stage, rank)
    local sec = (CFG.arena_coin_save - coin) / speed * 3600
    return utime.time_int() + math.floor(sec)
end

local function generate_defend(self, C)
    local arr = hinit.besthero_in_different_tab(self)
    local lineup = {}
    local order, zdl_sum = 0, 0
    local over
    for i = 1, BASIC.battlemax do
        for m = 1, TEAM do
            order = order + 1
            local info = arr[order]
            local linesub = utable.sub(lineup, m)
            if info then
                local uuid = info.uuid
                local hero = hinit.query(self, info.uuid)
                local _, zdl = hattrs.query(self, uuid)
                zdl_sum = zdl_sum + zdl
                insert(linesub, {
                    uuid = uuid,
                    pos = i,
                    id = hero.id,
                    level = hero.level,
                    zdl = zdl
                })
            else
                over = true
                if i > 1 then break end
            end
        end
        if over then break end
    end

    C.defends = lineup
    cache.dirty(self)
    roleinfo.changetable(self, {
        arena_defend_lineup = lineup,
        arena_defend_zdl = zdl_sum
    })
    return lineup
end

local function calc_defend_lineup(self, c)
    local zdl_sum = 0
    foreach(self, c, function(_, uuid, v)
        local hero = assert(hinit.query(self, uuid))
        local _, zdl = hattrs.query(self, uuid)
        zdl_sum = zdl_sum + zdl
        v.id = hero.id
        v.level = hero.level
        v.zdl = zdl
    end)
    roleinfo.changetable(self,
        {arena_defend_lineup = c, arena_defend_zdl = zdl_sum})
    return c
end

local function check_defend(self)
    local C = cache.get(self)
    if not C.defends then
        return generate_defend(self, C)
    else
        local lineup, zdl_sum, change = {}, 0, nil
        local exist

        for i, list in ipairs(C.defends) do
            local linesub = utable.sub(lineup, i)
            for _, v in ipairs(list) do
                local uuid = v.uuid
                local hero = hinit.query(self, uuid)
                if hero then
                    local _, zdl = hattrs.query(self, uuid)
                    zdl_sum = zdl_sum + zdl
                    exist = true
                    insert(linesub, {
                        uuid = uuid,
                        pos = v.pos,
                        id = hero.id,
                        level = hero.level,
                        zdl = zdl
                    })
                else
                    change = true
                end
            end
        end
        if not exist then
            return generate_defend(self, C)
        elseif change then
            C.defends = lineup
            C.zdl_sum = zdl_sum
            cache.dirty(self)
            roleinfo.changetable(self, {
                arena_defend_lineup = lineup,
                arena_defend_zdl = zdl_sum
            })
        end
        return lineup
    end
end

local function self_defend_zdl(self)
    local c = cache.getsub(self, "defends")
    local sum = 0
    foreach(self, c, function(_, uuid)
        local _, zdl = hattrs.query(self, uuid)
        sum = sum + zdl
    end)
    return sum
end

function _LUA.arena_get_detail(self)
    local C = cache.get(self)
    local lineup = calc_defend_lineup(self, C.defends)
    return {
        rid = self.rid,
        rname = self.rname,
        mainline = self.mainline,
        head = self.head,
        level = self.level,
        arena_coin_speed = coin_speed(self, C.stage, C.rank),
        arena_score_speed = score_speed(self, C.stage, C.rank),
        arena_defend_lineup = battle.multi_pack(lineup),
        arena_defend_zdl = self_defend_zdl(self)
    }
end

function _LUA.arena_battle_result(self, record, newstage, newrank, loginfo)
    skynet.call(arena_record, "lua", "add", self.rid, record)
    if loginfo then
        if record.finalwin == 1 then task.trigger(self, "fight_win") end
        flowlog.role(self, ARENA, loginfo)
    end

    local C = cache.get(self)
    if C.stage == newstage and C.rank == newrank then return end

    local time = record.time
    -- calc_full_time 函数中已经结算了coin
    client.push(self, "arena_full_time",
        {full_time = calc_full_time(self, C, time, newstage, newrank)})

    -- 新stage和rank存下来，新速率更新至roleinfo
    C.stage = newstage
    C.rank = newrank
    cache.dirty(self)
    update_speed(self, newstage, newrank)
end

skynet.init(function()
    CFG, CFG_RANK, CFG_STAGE, BASIC, CFG_MONEY =
        cfgproxy("arena", "arena_rank", "arena_stage", "basic", "money")
    arenad = skynet.uniqueservice("game/arenad")
    arena_record = skynet.uniqueservice("game/arena_record")
    fnopen.reg(ARENA, ARENA, function(self)
        arena_reg(self)
        check_defend(self)
    end)
end)

require("role.mods") {
    name = ARENA,
    loaded = function(self)
        if fnopen.check_open(self, ARENA) then
            check_season(self)
            check_defend(self)
        end
    end,
    enter = function(self)
        if fnopen.check_open(self, ARENA) then
            client.push(self, "arena_full_time", {
                full_time = calc_full_time(self, cache.get(self),
                    utime.time_int())
            })
        end
    end
}

local function free_times_used(self, now)
    now = now or utime.time_int()
    local C = cache.get(self)
    if not utime.same_day(C.times_update or 0, now) then
        C.times_used = 0
        C.times_update = now
        cache.dirty(self)
    end
    return C.times_used or 0
end

function _H.arena_info(self)
    if not fnopen.check_open(self, ARENA) then return {e = 0} end
    local C = cache.get(self)
    local now = utime.time_int()
    return {
        e = 0,
        coin = calc_coin(self, C, now),
        season_overtime = calc_season_overtime(now),
        stage = C.stage,
        rank = C.rank,
        arena_defend_zdl = self_defend_zdl(self),
        times_used = free_times_used(self, now)
    }
end

function _H.arena_range(self)
    if not fnopen.check_open(self, ARENA) then return {e = 1} end

    local C = cache.get(self)
    local list, dict, score =
        skynet.call(arenad, "lua", "arena_range", self.rid)
    local retlist = {}
    local success = roleinfo.query_list(dict, {"arena_defend_zdl"})
    for _, v in ipairs(list) do
        local rinfo = success[v.rid]
        rinfo.rank = v.rank
        insert(retlist, rinfo)
    end

    return {
        e = 0,
        coin = calc_coin(self, C, utime.time_int()),
        list = retlist,
        self = {
            arena_defend_zdl = self_defend_zdl(self),
            stage = C.stage,
            rank = C.rank,
            score = score
        }
    }
end

local MATCH
function _H.arena_match(self)
    if not fnopen.check_open(self, ARENA) then return {e = 1} end

    if MATCH then
        if utime.time_int() - MATCH.time < CFG.cd_time then
            return {e = 2}
        end
    end
    local list, matchlist, dict, time = {}, skynet.call(arenad, "lua",
        "arena_match", self.rid)
    if not next(matchlist) then return {e = 0, list = list} end

    local success = roleinfo.query_list(dict, {
        "arena_defend_zdl", "arena_defend_lineup"
    })

    local match = {}
    for _, one in ipairs(matchlist) do
        local info = success[one.rid]
        if info then
            info.rank = one.rank
            info.stage = one.stage
            info.arena_defend_lineup = battle.multi_pack(
                info.arena_defend_lineup)
            insert(list, info)
            match[info.rid] = info
        end
    end
    MATCH = {match = match, time = time}
    return {e = 0, list = list}
end

function _H.arena_detail(self, msg)
    if not fnopen.check_open(self, ARENA) then return {e = 1} end

    local rid = msg.rid
    local info
    if rid == self.rid then
        info = _LUA.arena_get_detail(self)
    else
        info = agent.call(rid, "lua", "arena_get_detail")
    end
    return {e = 0, info = info}
end

function _H.arena_query_defend(self)
    if not fnopen.check_open(self, ARENA) then return {e = 1} end

    local defends = calc_defend_lineup(self, cache.get(self).defends)
    return {e = 0, list = battle.multi_pack(defends)}
end

function _H.arena_set_defend(self, msg)
    if not fnopen.check_open(self, ARENA) then return {e = 1} end

    local list = battle.multi_unpack(msg.list)
    local defend, tab = {}, {}
    for i = 1, TEAM do
        local listsub = list[i]
        local defendsub = {}
        defend[i] = defendsub
        local cnt = 0
        for _, v in ipairs(listsub) do
            local uuid, postab = v.uuid, {}
            local hero = hinit.query(self, uuid)
            if not hero then
                return {e = 3}
            else
                local pos = v.pos
                if not pos or postab[pos] or pos > BASIC.battlemax then
                    return {e = 2}
                end
                postab[pos] = true

                local hero_cfg = hinit.query_cfg_byid(self, hero.id)
                local ttab = hero_cfg.tab
                if tab[ttab] then return {e = 4} end
                tab[ttab] = true
            end
            insert(defendsub, {uuid = v.uuid, pos = v.pos})
            cnt = cnt + 1
        end
        if cnt > BASIC.battlemax then return {e = 6} end
    end
    if not next(tab) then return {e = 5} end
    cache.get(self).defends = defend
    cache.dirty(self)

    calc_defend_lineup(self, defend)
    return {e = 0}
end

function _H.arena_records(self)
    if not fnopen.check_open(self, ARENA) then return {e = 1} end
    return {e = 0, records = skynet.call(arena_record, "lua", "get", self.rid)}
end

local function calc_got(self, coin)
    local coin_max = CFG_MONEY[awardtype.arena_coin].max

    local rest = coin_max - award.getcnt(self, awardtype.arena_coin)
    return rest > 0 and math.min(rest, coin)
end

function _H.arena_get_coin(self)
    if not fnopen.check_open(self, ARENA) then return {e = 1} end
    local C = cache.get(self)

    local now = utime.time_int()
    local coin = calc_coin(self, C, now)
    if coin <= 0 then return {e = 3} end

    local got = calc_got(self, coin)
    if not got then return {e = 2} end

    C.coin = coin - got
    cache.dirty(self)

    -- 此处只是领coin，stage和rank前后没有变化
    client.push(self, "arena_full_time",
        {full_time = calc_full_time(self, C, now)})

    local option = {flag = "arena_get_coin", arg1 = got}
    assert(award.add(self, option, {{awardtype.arena_coin, 0, got}}))
    return {e = 0, got = got}
end

local function create_multi(self, bi)
    local teamlist, teaminfo = {}, {}
    for i = 1, TEAM do
        local _list = bi.multi_list[i]
        if not _list or not next(_list.list) then return false, 5 end

        local list, list_save
        local ll = _list.list
        list, list_save = m_battle.check_bi(self, {
            auto = bi.auto,
            list = ll,
            multi_speed = bi.multi_speed
        })
        if not list then return false, list_save end

        local heroes, err = m_battle.create_heroes(self, list, {})
        if not heroes then return false, err end

        teamlist[i] = heroes
        teaminfo[i] = list
    end
    return {
        rid = self.rid,
        rname = self.rname,
        level = self.level,
        head = self.head,
        gname = self.gname
    }, teamlist, teaminfo
end

function _LUA.create_multi_defend(self)
    local teamlist, teaminfo = {}, {}
    for i, ll in ipairs(cache.getsub(self, "defends")) do
        if #ll > 0 then
            local list, list_save = m_battle.check_lineup(self, ll)
            if not list then return false, list_save end

            local heroes, err = m_battle.create_heroes(self, list, {})
            if not heroes then return false, err end

            teamlist[i] = heroes
            teaminfo[i] = list
        end
    end
    return {
        rid = self.rid,
        rname = self.rname,
        level = self.level,
        head = self.head,
        gname = self.gname
    }, teamlist, teaminfo
end

function _LUA.arena_check_cost(self, bi, logs)
    local left, leftlist, leftinfo = create_multi(self, bi)
    if not left then return false, leftlist end

    local C = cache.get(self)
    if free_times_used(self) < CFG.free then
        C.times_used = (C.times_used or 0) + 1
        cache.dirty(self)
    else
        if not award.del(self, logs, {CFG.cost}) then return false, 4 end
    end
    return left, leftlist, leftinfo
end

-- 新赛季开始，stage继承上赛季，rank则清空
function _LUA.arena_new_season(self)
    if fnopen.check_open(self, ARENA) then
        local C = cache.get(self)
        local now = utime.time_int()

        -- 先用旧速率结算coin，用新速率去算full_time
        client.push(self, "arena_full_time",
            {full_time = calc_full_time(self, C, now, C.stage)})

        -- 再在agent中更新stage 和rank
        C.rank = nil
        cache.dirty(self)
        update_speed(self, C.stage)
    end
end

local function create_leftsave(leftinfo)
    local leftsave = {}
    for i = 1, TEAM do
        local list = {}
        leftsave[i] = list
        for _, v in ipairs(leftinfo[i] or {}) do
            insert(list, {uuid = v.uuid, pos = v.pos})
        end
    end
    return leftsave
end

function _H.arena_battle_fight(self, msg)
    if not fnopen.check_open(self, ARENA) then return {e = 1} end
    local rid, bi = msg.rid, msg.battle_info

    if not MATCH then return {e = 2} end
    local match = MATCH.match[rid]
    if not match then return {e = 3} end

    local time = MATCH.time
    if not same_season(time, utime.time_int() + CFG.settle_cd) then
        return {e = 10}
    end

    local C = cache.get(self)
    local logs = {flag = "arena_battle_fight", arg1 = rid}

    local ctx = {
        lrid = self.rid,
        rrid = match.rid,
        addr = self.addr,
        lstage = C.stage,
        lrank = C.rank,
        time = time,
        rstage = match.stage,
        rrank = match.rank,
        bi = bi,
        fd = self.fd,
        logs = logs
    }
    local ok, leftinfo = skynet.call(arenad, "lua", "arena_battle_fight", ctx)
    if not ok then return {e = leftinfo} end

    MATCH = nil
    m_battle.set_lineup(self, ARENA, create_leftsave(leftinfo), true)
    task.trigger(self, "fight")

    flowlog.role(self, ARENA, {opt = "battle_fight", rrid = rid})

    return {e = 0, times_used = C.times_used}
end

m_report.reg(ARENA, function(self, key, replayid)
    return skynet.call(arena_record, "lua", "find_report", self.rid, key,
        replayid)
end)

event.reg("EV_HERO_DELS", ARENA, function(self, uuids)
    local c = cache.getsub(self, "defends")
    for _, _uuid in ipairs(uuids) do
        foreach(self, c, function(_, uuid)
            if uuid == _uuid then
                check_defend(self)
                return true
            end
        end)
    end
end)

local function event_reg(EV_NAME)
    event.reg(EV_NAME, ARENA, function(self, uuid_dict)
        local c = cache.getsub(self, "defends")
        for _uuid in pairs(uuid_dict) do
            foreach(self, c, function(_, uuid)
                if _uuid == uuid then
                    calc_defend_lineup(self, c)
                    return true
                end
            end)
        end
    end)
end

event_reg("EV_HERO_STAGEUP")
event_reg("EV_HERO_ATTRS_CHANGE")
