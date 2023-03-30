local battlerun = require "battle.run"
local skynet = require "skynet"
local trigger = require "battle.trigger"
local camp_type = require "battle.camp_type"
local service = require "service"
local ptype = require "skillsys.passive_type"
local log = require "log"
local b_util = require "battle.util"
local _LUA = require "handler.lua"
local _BG = require "battle.global"
local skillsys = require "skillsys.skill_sys"
local stat = require "battle.stat"
local bco = require "battle.coroutine"
local profile = require "battle.profile"
local object = require "battle.object"
require "util"
local _M = {}
local quiting = nil

local function check_wakeup(bctx)
    if not bctx.real_start then
        bctx.real_start = true
        bco.wakeup(bctx, bctx.co)
    else
        local btime = bctx.btime
        if btime.ispause then btime.pause(bctx, false) end
    end
end

local function check_joined(plys)
    local battle_list = battlerun.battle_list()
    for _, ply in pairs(plys) do
        if battle_list[ply.rid] then return false end
    end
    return true
end

function _LUA.battle_start(bctx, left, right)
    local response = skynet.response()
    if quiting then
        battlerun.abort(bctx, response, "quiting")
        return service.NORET
    end
    if not check_joined(bctx.plys) then
        battlerun.abort(bctx, response, "battling")
        return service.NORET
    end
    local ok, err = xpcall(battlerun.start, debug.traceback, bctx, response,
        left, right)
    if not ok then
        log("%s", err)
        ldump({bctx = bctx, left = left, right = right})
        battlerun.abort(bctx, response, "start abort")
    end
    return service.NORET
end

function _LUA.battle_real_start(rid)
    local bctx = battlerun.get_ctx(rid)
    if not bctx then return end
    if not bctx.real_start then
        bctx.real_start = true
        bco.wakeup(bctx, bctx.co)
    end
end

function _LUA.battle_terminate(rid, restart)
    local bctx = battlerun.get_ctx(rid)
    if not bctx then return end
    bctx.restart = restart
    bctx.terminate = true
    check_wakeup(bctx)
end

function _LUA.battle_accelerate(rid, multi_speed)
    local bctx = battlerun.get_ctx(rid)
    if not bctx then return end
    battlerun.set_multi(bctx, multi_speed or 1)
end

local function _pause(bctx, pause)
    bctx.btime.pause(bctx, pause)
end

_BG.pause = _pause

function _LUA.battle_pause(rid, pause)
    local bctx = battlerun.get_ctx(rid)
    if not bctx then return end
    if not bctx.real_start then return end
    _pause(bctx, pause)
end

function _LUA.battle_auto(rid, auto)
    local bctx = battlerun.get_ctx(rid)
    if not bctx then return end
    bctx.auto = auto
end

function _LUA.use_skill(rid, heroid)
    local bctx = battlerun.get_ctx(rid)
    if not bctx then return 6 end
    local obj = bctx.objmgr.get(heroid)
    if not obj then return 3 end
    local skillid = obj.combo_skill
    if not skillsys.check_skillcd(bctx, obj, skillid) then return 4 end
    local ok, e = obj:use_skill(bctx, skillid)
    if not ok then return e end
    _BG.record_skill(bctx, heroid, skillid)
    return 0
end

function _LUA.battle_offline(rid)
    local bctx = battlerun.get_ctx(rid)
    if not bctx then return end
    if bctx.offline_skip then
        battlerun.set_timeskip(bctx)
        bctx.objmgr.set_skip()
    else
        bctx.terminate = true
    end
    _pause(bctx, false)
    check_wakeup(bctx)
end

function _LUA.battle_skip(rid)
    local bctx = battlerun.get_ctx(rid)
    if not bctx then return 1 end
    battlerun.set_timeskip(bctx)
    bctx.objmgr.set_skip()
    _pause(bctx, false)
    return 0
end

function _LUA.get_monitor()
    local d = profile.monitor_info()
    d.cnt = battlerun.onlinecnt()
    d.msgsz = stat.get_msgsz()
    return d
end

function _BG.add_clone(bctx, o)
    battlerun.add_obj(bctx, o)
end

function _BG.add_trigger(bctx, trigger_id, x, y, owner, target)
    local o = trigger(bctx, trigger_id, x, y, owner, target)
    battlerun.add_obj(bctx, o)
end

function _BG.get_traits_cnt(bctx, self, tag_id, tag_v)
    local traits = bctx.traits
    if not traits then
        traits = {[camp_type.left] = {}, [camp_type.right] = {}}
        bctx.traits = traits
    end
    local traits_camp = traits[self.camp]
    local tag_name = b_util.get_tag_type(tag_id)
    local key = tag_name .. "_" .. tag_v
    if traits_camp[key] then return traits_camp[key] end

    local list = self.camp == camp_type.left and bctx.left or bctx.right
    local cnt = 0
    for _, o in pairs(list) do
        if o[tag_name] == tag_v and object.check_hero(o) then
            cnt = cnt + 1
        end
    end
    traits_camp[key] = cnt
    return cnt
end

function _BG.friend_hero_cnt(bctx, self)
    local objs = bctx.objs
    return objs.get_cnt(self.camp)
end

function _BG.enemy_hero_cnt(bctx, self)
    local objs = bctx.objs
    local enemy_camp = camp_type(self.camp)
    return objs.get_cnt(enemy_camp)
end

function _BG.use_combo(bctx, self, tobj)
    local camp = self.camp
    local cmders = bctx.cmders
    local enemy_camp = camp_type(camp)
    local cmder_enemy = cmders[enemy_camp]
    if cmder_enemy then
        if not cmder_enemy.enemy_first_use_combo then
            cmder_enemy.enemy_first_use_combo = true
            _BG.passive_trigger(bctx, ptype.first_use_combo_enemy, cmder_enemy,
                self)
        end
    end
    if not self.first_use_combo then
        self.first_use_combo = true
        _BG.passive_trigger(bctx, ptype.first_use_combo, self, tobj)
    end
end

function _BG.record_skill(bctx, heroid, skillid)
    local skill_used_list = bctx.skill_used_list
    if not skill_used_list then
        skill_used_list = {}
        bctx.skill_used_list = skill_used_list
    end
    local frame = bctx.btime.frame
    table.insert(skill_used_list,
        {frame = frame, heroid = heroid, skillid = skillid})
end

function _LUA.run_over()
    quiting = 1
    local battle_list = battlerun.battle_list()
    while next(battle_list) do
        skynet.sleep(1000)
        if quiting == 2 then return end
    end
    skynet.send(skynet.self(), "lua", "stop")
end

function _M.release()
    quiting = 2
    local battle_list = battlerun.battle_list()
    for _, bctx in pairs(battle_list) do
        bctx.terminate = true
        check_wakeup(bctx)
    end
    while next(battle_list) do skynet.sleep(10) end
end

return _M
