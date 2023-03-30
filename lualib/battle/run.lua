-- mods reg order
require "skillsys.attrcalc"
require "battle.status"
require "skillsys.passive"
require "skillsys.skill_sys"
require "skillsys.buffsys"
--
local skynet = require "skynet"
local time = require "battle.time"
local timer = require "timer"
local obj_list = require "battle.obj_list"
local json = require "rapidjson.c"
local b_util = require "battle.util"
local commander = require "battle.commander"
local hero = require "battle.hero"
local profile = require "battle.profile"
local traceback = debug.traceback
local utable = require "util.table"
local camp_type = require "battle.camp_type"
local win_type = require "battle.win_type"
local cfgdata = require "cfg.data"
local cfgbase = require "cfg.base"
local _BG = require "battle.global"
local ptype = require "skillsys.passive_type"
local bco = require "battle.coroutine"
local ceilmap = require "battle.objmgr"

local random = require "battle.random"
local uniq = require "uniq.c"
local battle_list = {}
local BASIC, SCENE_CFG, POS_CFG, SOULBAND_CFG
local replaylib = require "replay"
local floor = math.floor
local ceil = math.ceil
local max = math.max

local profile_add = profile.add
local wintype_win = win_type.win
local wintype_lose = win_type.lose
local stat_push = require"battle.stat".push
local pause_timeout

local remove = table.remove
local next = next
local xpcall = xpcall
local b_util_now = b_util.now
local skynet_now = skynet.now
local ulog = b_util.log
local function log(bctx, ...)
    ulog(bctx, ...)
end

local _M = {}
local CNT, TOTAL = 0, 0

skynet.init(function()
    BASIC, SCENE_CFG, POS_CFG, SOULBAND_CFG = cfgdata.basic, cfgdata.scenemap,
        cfgdata.battlemap, cfgdata.soulband
    pause_timeout = BASIC.battle_timeout * 100
    cfgbase.stopall()
end)

local function abort(bctx, response, why)
    if bctx and not bctx.abort then
        bctx.abort = true
        for _, ply in pairs(bctx.plys) do battle_list[ply.rid] = nil end
        response(false, why or "abort")
    end
end

local function pack_replay(bctx, uuid, win, fight_cost, frame)
    local replay
    if bctx.MM then
        local MM = bctx.MM
        replay = {
            uuid = uuid,
            ti = skynet.time(),
            ctx = {
                uuid = uuid,
                limit = replaylib.limit_filter(bctx.limit),
                no_play = bctx.no_play,
                pvp = bctx.pvp,
                multi_speed = 1,
                nm = bctx.nm,
                win = win,
                isreplay = true,
                seed = bctx.seed,
                mapid = bctx.mapid,
                skill_used_list = bctx.skill_used_list
            },
            fight_cost = fight_cost,
            total_frame = frame,
            ver = BASIC.battle_ver,
            left = json.decode(MM.left),
            right = json.decode(MM.right),
            error = bctx.error
        }
    end
    return replay
end

local function copy_attr(o)
    local dead = o.report.dead
    local r = {
        hp = dead and 0 or o.attrs.hp,
        tpv = o.attrs.tpv,
        hurt = o.report.hurt,
        dead = dead
    }
    return r
end

local function pack_report(bctx, uuid, win)
    local l_ret, r_ret = {}, {}
    local l_report_data, r_report_data = {}, {}
    local report = {
        uuid = uuid,
        win = win,
        left = {heroes = l_report_data, player = bctx.lplayer},
        right = {heroes = r_report_data, player = bctx.rplayer}
    }
    for _, o in ipairs(bctx.left) do
        l_ret[o.id] = copy_attr(o)
        table.insert(l_report_data, o.report)
    end
    for _, o in ipairs(bctx.right) do
        r_ret[o.id] = copy_attr(o)
        table.insert(r_report_data, o.report)
    end
    return report, l_ret, r_ret
end

local function battle_over(bctx)
    TOTAL = TOTAL + 1
    CNT = CNT - 1
    local total_time = b_util_now() - bctx.start_ti
    profile.set(bctx, bctx, "total_cost", total_time)
    local total_frame = bctx.btime.frame
    profile.set(bctx, bctx, "total_frame", total_frame)
    local fight_cost = profile.get(bctx, "fight_cost")
    local alert = profile.check_maxcost(fight_cost)
    if not alert and not bctx.error and not bctx.verify then
        if bctx.nm == "robot" then bctx.MM = nil end
    end

    if bctx.terminate then bctx.MM = nil end

    for _, ply in pairs(bctx.plys) do battle_list[ply.rid] = nil end
    local uuid = bctx.uuid
    local win = bctx.win or wintype_lose
    local report, l_ret, r_ret = pack_report(bctx, uuid, win)
    local replay = pack_replay(bctx, uuid, win, fight_cost, total_frame)
    if replay then replaylib.add(replay) end
    local ret = {
        win = win,
        report = report,
        left = l_ret,
        right = r_ret,
        restart = bctx.restart,
        terminate = bctx.terminate,
        replay = replay,
        totaltime = floor(total_time / 1000)
    }

    local cmder = bctx.cmders[camp_type.left]
    if not bctx.pvp and ret.win == wintype_win then
        local show_id = bctx.final_kill
        local o = bctx.objmgr.get(show_id)
        if o then
            stat_push(bctx, cmder, "battle_final_kill",
                {uuid = o.id, cfgid = o.cfgid}, true)
        end
    end
    stat_push(bctx, cmder, "battle_over", {}, true)

    if bctx.dump then profile.dump(bctx) end

    profile.result(bctx)
    bctx.response(true, ret)
end

local camp_type_left<const> = camp_type.left
local camp_type_right<const> = camp_type.right

local function check_finish(bctx)
    local win
    local get_cnt = bctx.objs.get_cnt
    if bctx.terminate then
        win = wintype_lose
        log(bctx, "battle terminate")
    elseif get_cnt(camp_type_left) <= 0 then
        win = wintype_lose
    elseif get_cnt(camp_type_right) <= 0 then
        win = wintype_win
    elseif bctx.btime.now >= BASIC.battletime * 100 then
        win = wintype_lose
    end
    -- 保持录像的战斗结果
    bctx.win = bctx.win or win
    return win ~= nil
end

local function update_obj(bctx, o, preskill)
    local deep = {}
    bctx.deep = deep
    local ok, err = xpcall(o.update, traceback, o, bctx, preskill)
    bctx.deep = nil
    if not ok then
        bctx.error = true
        bctx.MM = bctx.bak
        skynet.error("%s", err)
    end
end

local function prepare_skill(bctx, frame)
    local skill_used_list = bctx.skill_used_list
    if skill_used_list then
        local objmgr = bctx.objmgr
        local skill_data = skill_used_list[1]
        while skill_data do
            if skill_data.frame ~= frame then break end
            local obj = objmgr.get(skill_data.heroid)
            obj.prepared_skill = skill_data.skillid
            obj.next_up_ti = nil
            remove(skill_used_list, 1)
            skill_data = skill_used_list[1]
        end
        if not skill_used_list[1] then bctx.skill_used_list = nil end
    end
end

local function battle_pause(bctx, co)
    local wait_ti = skynet_now()
    bco.wait(bctx, co, 2, pause_timeout, {terminate = true})
    stat_push(bctx, bctx, "battle_continue", {ti = bctx.btime.now})
    bctx.next_frame_ti = bctx.next_frame_ti + (skynet_now() - wait_ti)
end

local mxa_framecost = 0
local function one_frame(bctx, co)
    local hti = b_util_now()
    local fightcost = 0
    local btime = bctx.btime
    local isreplay = bctx.isreplay
    if isreplay then prepare_skill(bctx, btime.frame) end
    for _, o in pairs(bctx.objs) do
        local skillid = o.prepared_skill
        if skillid then o.prepared_skill = nil end
        update_obj(bctx, o, skillid)
        if btime.ispause then
            fightcost = fightcost + (b_util_now() - hti)
            battle_pause(bctx, co)
            hti = b_util_now()
        end
        if check_finish(bctx) then return false end
    end
    btime.update()
    local framecost = fightcost + b_util_now() - hti
    profile_add(bctx, bctx, "fight_cost", framecost)
    if framecost > mxa_framecost then
        mxa_framecost = framecost
        bctx.verify = true
        log(bctx, "max framecost %f", mxa_framecost)
    end
    if bctx.frame_dump then log(bctx, "framecost=%f", framecost) end
    return true
end

local max_loop<const> = 10
local function update(bctx)
    local uuid = bctx.uuid
    local btime = bctx.btime
    local btime_granule = btime.granule
    local co = bctx.co
    btime.start(co)
    local start_ti = skynet_now()
    bctx.next_frame_ti = start_ti
    while true do
        if bctx.abort then return log(bctx, "battle update abort") end
        if bctx.terminate then
            log(bctx, "battle update terminate1")
            break
        end
        if btime.ispause then battle_pause(bctx, co) end
        if bctx.terminate then
            log(bctx, "battle update terminate2")
            break
        end
        local loop = 0
        local granule = btime_granule()
        local continue
        local ti = skynet_now()
        for _ = 1, max_loop do
            if ti < bctx.next_frame_ti then break end
            continue = one_frame(bctx, co)
            loop = loop + 1
            bctx.next_frame_ti = bctx.next_frame_ti + granule
            if not continue then break end
        end
        if not continue then break end

        local delay = max(0, ceil(bctx.next_frame_ti - skynet_now()))
        bco.wait(bctx, co, 1, max(0, delay))
    end
    if not bctx.terminate then
        local maxdelay = skynet_now() - bctx.next_frame_ti
        profile.set(bctx, bctx, "max_delay", max(0, maxdelay * 10))
    end
    battle_over(bctx)
end

local function add_obj(bctx, o)
    bctx.objs.add(o)
end

local function init_commanders(bctx, l_o, r_o, l_ave_level, r_ave_level)
    local cmders = utable.getsub(bctx, "cmders")
    local passive_list = bctx.passive_list

    local l_cmder = commander(bctx, camp_type.left, l_o, passive_list.left,
        l_ave_level)
    cmders[camp_type.left] = l_cmder
    add_obj(bctx, l_cmder)
    local r_cmder = commander(bctx, camp_type.right, r_o, passive_list.right,
        r_ave_level)
    cmders[camp_type.right] = r_cmder
    add_obj(bctx, r_cmder)
end

local function check_soulband(obj, objs)
    local passive_list = obj.passive_list
    if obj.soulband then
        passive_list = passive_list or {}
        local cfg = SOULBAND_CFG[obj.soulband]
        local condition = cfg.condition
        local cnt = 0
        local r = {}
        for _, o in pairs(objs) do
            local tab = o.tab
            if condition[tab] and not r[tab] then
                r[tab] = true
                cnt = cnt + 1
            end
        end
        for _, v in ipairs(cfg.effect) do
            if cnt >= v[1] then
                for i = 2, #v do table.insert(passive_list, v[i]) end
                break
            end
        end
        obj.passive_list = passive_list
    end
end

local function init_heroes(bctx, left, right, poscfg, l_ave_level, r_ave_level)
    bctx.hero_initializing = true

    local pre_left = {}
    for _, o in ipairs(left) do
        check_soulband(o, left)
        local camp = camp_type.left
        add_obj(bctx, hero(bctx, o, camp, poscfg[camp][o.pos], l_ave_level))
        table.insert(pre_left, o.cfgid)
    end
    local pre_right = {}
    for _, o in ipairs(right) do
        check_soulband(o, right)
        local camp = camp_type.right
        add_obj(bctx, hero(bctx, o, camp, poscfg[camp][o.pos], r_ave_level))
        table.insert(pre_right, o.cfgid)
    end
    bctx.hero_initializing = nil
    stat_push(bctx, bctx, "battle_prepare_heroes",
        {left = pre_left, right = pre_right})
end

local function cnt_change(bctx, camp, cnt)
    if not bctx.hero_initializing then
        local cmders = bctx.cmders
        local enemy_camp = camp_type(camp)
        _BG.passive_trigger_Bi(bctx, ptype.friend_hero_change,
            ptype.enemy_hero_change, cmders[camp], cmders[enemy_camp])
    end
end

local function init_objs(bctx, left, right, poscfg)
    bctx.objs = obj_list({
        bctx = bctx,
        inc_cnt = cnt_change,
        dec_cnt = cnt_change
    })
    local l_level, r_level = 0, 0
    for _, o in ipairs(left) do l_level = l_level + o.level end
    local l_ave_level = ceil(l_level / #left)
    for _, o in ipairs(right) do r_level = r_level + o.level end
    local r_ave_level = ceil(r_level / #right)

    local l_copy, r_copy = utable.copy(left[1]), utable.copy(right[1])
    init_heroes(bctx, left, right, poscfg, l_ave_level, r_ave_level)
    init_commanders(bctx, l_copy, r_copy, l_ave_level, r_ave_level)
    stat_push(bctx, bctx, "battle_addhero_over", {})
end

local function battle_run(bctx)
    local co = coroutine.running()
    bctx.co = co
    if not bctx.real_start then
        bco.wait(bctx, co, 1, BASIC.ready_fight * 100)
    end
    bctx.start_ti = b_util_now()
    local ok, err = xpcall(update, debug.traceback, bctx)
    if not ok then
        CNT = CNT - 1
        skynet.error("%s", err)
        abort(bctx, bctx.response, "run error")
    end
end

function _M.start(bctx, response, left, right)
    local seed = bctx.seed or skynet.now() // 100
    bctx.seed = seed

    -- to delete
    if not bctx.isreplay and bctx.nm ~= "robot" then bctx.save = true end

    bctx.uuid = tostring(bctx.uuid or (bctx.save and uniq.uuid() or uniq.id()))
    bctx.bak = {left = json.encode(left), right = json.encode(right)}
    if bctx.save then bctx.MM = bctx.bak end
    bctx.response = response
    bctx.btime = time()
    bctx.random = random.setseed(seed)

    bctx.left, bctx.lplayer = left.heroes, left.player
    bctx.right, bctx.rplayer = right.heroes, right.player
    bctx.passive_list = {left = left.passive_list, right = right.passive_list}
    local mapid = assert(bctx.mapid)
    local cfg = SCENE_CFG[mapid]
    if not bctx.pvp then bctx.no_timestop = cfg.no_timestop end
    local poscfg = POS_CFG[cfg.box_gid]
    local width, height = cfg.size[1], cfg.size[2]
    local objmgr = ceilmap(width, height, cfg.stop)
    for _, ply in pairs(bctx.plys) do
        battle_list[ply.rid] = bctx
        objmgr.add_ply(ply)
    end
    bctx.objmgr = objmgr
    _M.set_multi(bctx, bctx.multi_speed or 1)

    if bctx.skip then
        bctx.real_start = true
        _M.set_timeskip(bctx)
    end

    profile.init(bctx)
    init_objs(bctx, bctx.left, bctx.right, poscfg)
    skynet.fork(battle_run, bctx)
    CNT = CNT + 1
end

function _M.set_multi(bctx, multi)
    bctx.btime.set_multi(multi)
end

function _M.set_timeskip(bctx)
    bctx.btime.set_skip()
end

function _M.get_ctx(rid)
    local bctx = battle_list[rid]
    return bctx
end

function _M.battle_list()
    return battle_list
end

function _M.onlinecnt()
    return CNT
end

function _M.total()
    return TOTAL
end

_M.add_obj = add_obj
_M.abort = abort

return _M
