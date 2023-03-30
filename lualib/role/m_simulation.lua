local skynet = require "skynet"
local cfgdata = require "cfg.data"
local client = require "client.mods"
local fnopen = require "role.fnopen"
local award = require "role.award"
local m_battle = require "role.m_battle"
local hattrs = require "hero.attrs"
local utable = require "util.table"
local utime = require "util.time"
local flowlog = require "flowlog"
local roleinfo = require "roleinfo"
local zset = require "zset"
local battle = require "battle"
local m_report = require "role.m_report"
local zsettype = require "zset.type"
local task = require "task"
local event = require "role.event"
local schema = require "mongo.schema"
local cache = require("mongo.role")("simulation")

cache.schema(schema.OBJ {
    update = schema.ORI,
    cnt = schema.NOBJ(),
    floor = schema.NOBJ()
})

local _H = require "handler.client"
local _M = {}

local NM<const> = "simulation"

local function update_check(self, C)
    local now = utime.time()
    if not utime.same_day(now, C.update or 0) then
        C.update = now
        C.cnt = {}
        cache.dirty(self)
    end
end

local function enter_push(self)
    if fnopen.check_open(self, NM) then
        local C = cache.get(self)
        update_check(self, C)
        client.enter(self, NM, "simulation_info", C)
    end
end

local MGR, ZSERANK
skynet.init(function()
    MGR = skynet.uniqueservice("game/simulation")
    ZSERANK = skynet.uniqueservice("base/zsetrank")
    fnopen.reg(NM, NM, enter_push)
end)

require("role.mods") {name = NM, enter = enter_push}

local function lineup_zdl(self, list)
    local total = 0
    for _, v in ipairs(list) do
        local _, zdl = hattrs.query(self, v.uuid)
        total = total + zdl
    end
    return total
end

local function do_record(self, feature, floor, list, report)
    zset.set(zsettype[NM .. feature], {
        id = self.rid,
        value = floor,
        sid = self.sid,
        time = utime.time()
    })
    skynet.send(MGR, "lua", "save", feature, floor, {
        rid = self.rid,
        zdl = lineup_zdl(self, list),
        replayid = report.uuid
    }, report)
end

function _M.simu(self, feature, floor)
    if not fnopen.check_open(self, NM) then
        return false, "fnopen check failed"
    end
    if not cfgdata.simulation[feature] then return false, "no cfg" end

    local cachefloor = cache.getsub(self, "floor")
    cachefloor[feature] = floor
    cache.dirty(self)

    enter_push(self)
    return true
end

function _H.simulation_start(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end

    local feature = msg.feature
    local cfg = cfgdata.simulation[feature]
    if not cfg then return {e = 2} end

    if self.mainline < cfg.condition then return {e = 3} end

    local opentime = cfg.opentime
    if opentime and not utable.array_find(opentime, utime.wday(utime.time())) then
        return {e = 4}
    end

    local C = cache.get(self)
    local cnt = C.cnt[feature] or 0
    if cfg.num and cnt >= cfg.num then return {e = 5} end

    local cachefloor = cache.getsub(self, "floor")
    local floor_now = cachefloor[feature] or 0
    local floor = floor_now + 1

    local cfg_floor = cfg.floors[floor]
    if not cfg_floor then return {e = 6} end

    local bi = msg.battle_info

    local list, list_save = m_battle.check_bi(self, bi)
    if not list then return {e = list_save} end

    if not m_battle.check_feature(self, list, feature) then return {e = 7} end

    local left, err = m_battle.create_heroes(self, list)
    if not left then return {e = err} end
    local right = m_battle.create_monsters(cfg_floor.monster)

    local ctx<close> = battle.create(NM, cfg.battle, {
        auto = bi.auto,
        multi_speed = bi.multi_speed,
        no_play = bi.no_play,
        save = true
    })
    if not battle.join(ctx, self) then return {e = 106} end

    battle.start(ctx, left, right, function(ok, ret)
        if not ok then return battle.abnormal_push(self) end
        local _floor_now = cachefloor[feature] or 0
        if ret.restart or ret.terminate or _floor_now ~= floor_now then
            return battle.push(self, ret)
        end
        local win = ret.win
        local reward
        if win == 1 then
            cachefloor[feature] = floor
            C.cnt[feature] = cnt + 1
            cache.dirty(self)
            reward = cfg_floor.reward
            award.adde(self, {
                flag = NM,
                arg1 = feature,
                arg2 = floor,
                theme = {"SIMULATUIB_FULL_THEME_{1}_", floor},
                content = {"SIMULATUIB_FULL_CONTENT_{1}_", floor}
            }, reward)

            do_record(self, feature, floor, list, ret.report)

            local tasktype = cfg.tasktype
            if tasktype then
                local val, min = floor, math.maxinteger
                if feature ~= 0 then
                    for _, v in ipairs(cfgdata.simulation_features) do
                        min = math.min((cachefloor[v] or 0), min)
                    end
                    val = min
                end
                task.trigger(self, tasktype, val)
            end
        end
        task.trigger(self, "simu_fight")
        client.push(self, NM, "simulation_result", {
            endinfo = battle.battle_endinfo(ret, reward),
            feature = feature
        })
    end)

    m_battle.set_lineup(self, NM .. feature, list_save)
    flowlog.role_act(self,
        {flag = "simulation_start", arg1 = feature, arg2 = floor})
    return {e = 0}
end

function _H.simulation_records(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local feature, floor = msg.feature, msg.floor
    local cfg = cfgdata.simulation[feature]
    if not cfg then return {e = 2} end
    if not cfg.floors[floor] then return {e = 3} end
    local records = skynet.call(MGR, "lua", "query", feature, floor)

    for _, record in ipairs(records) do
        local info = roleinfo.query(record.rid)
        record.rname = info.rname
        record.level = info.level
        record.head = info.head
    end
    return {e = 0, records = records}
end

function _H.simulation_zset(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local feature = msg.feature
    local data, rank, selfobj = skynet.call(ZSERANK, "lua", "query_rank",
        self.rid, zsettype[NM .. feature])
    local ret
    if selfobj then
        ret = {
            rid = self.rid,
            head = self.head,
            rname = self.rname,
            level = self.level,
            time = selfobj.time,
            rank = rank,
            value = selfobj.value
        }
    end
    return {e = 0, data = data, self = ret}
end

m_report.reg(NM, function(_, replayid)
    local info = skynet.call(MGR, "lua", "query_replayid", replayid)
    if not info then return false end
    return info.report
end)

event.reg("EV_UPDATE", NM, enter_push)

return _M
