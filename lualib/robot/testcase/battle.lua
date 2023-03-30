local skynet = require "skynet"
local net = require "robot.net"
local timer = require "timer"
local log = require "log"
local cfgproxy = require "cfg.proxy"
local _H = require "handler.client"
local chat = require "robot.chat"
require "util"

local uniq = require "uniq.c"
local BASIC, GENERAL_SKILLS, NORMAL_SKILLS, COMBO_SKILLS, HERO_IDS, ATTRIBUTE,
    PASSIVE_IDS, HERO, SKILL_CFG

skynet.init(function()
    BASIC, GENERAL_SKILLS, NORMAL_SKILLS, COMBO_SKILLS, HERO_IDS, ATTRIBUTE, PASSIVE_IDS, HERO, SKILL_CFG =
        cfgproxy("basic", "hero_general_ids", "hero_skill_ids",
            "hero_combo_ids", "hero_hero_ids", "attribute",
            "passive_effect_ids", "hero_monster", "skill")
end)

local _M = {}

local function rand_hero2(pos)
    local idx1 = math.random(#HERO_IDS)
    local cfgid = HERO_IDS[idx1]
    local hero = {
        id = uniq.id(),
        cfgid = cfgid,
        level = math.random(1, 500),
        pos = pos,
        boss = math.random(1, 2) - 1
    }
    local tag_type = BASIC.condition_hero
    local tagv_max = BASIC.robot_condition_hero or {5, 11, 2, 2}
    for i, tag in ipairs(tag_type) do
        local max = tagv_max[i]
        local val = math.random(1, max)
        hero[tag] = val
    end

    local herocfg = HERO[cfgid]
    local skilllist = {herocfg.general_skill}
    for _, vv in ipairs(herocfg.skill) do
        local i = math.random(#vv)
        local skillid = vv[i][2]
        table.insert(skilllist, skillid)
    end
    if herocfg.combo and next(herocfg.combo) then
        local i = math.random(#herocfg.combo)
        local skillid = herocfg.combo[i][2]
        hero.combo_skill = skillid
    end
    hero.skilllist = skilllist

    -- 被动技能
    local passive_list = {}
    local cnt = 0
    while cnt < 5 do
        local i = math.random(#PASSIVE_IDS)
        table.insert(passive_list, PASSIVE_IDS[i])
        cnt = cnt + 1
    end
    hero.passive_list = passive_list

    local attrs = {}
    for k, v in pairs(ATTRIBUTE) do
        local val = math.random(v.max[1], v.max[2])
        attrs[k] = val
    end
    hero.baseattrs = attrs
    return hero
end

local function rand_hero(pos)
    local idx1 = math.random(#HERO_IDS)
    local cfgid = HERO_IDS[idx1]
    local hero = {
        id = uniq.id(),
        cfgid = cfgid,
        level = math.random(1, 500),
        pos = pos,
        boss = math.random(1, 2) - 1
    }
    local tag_type = BASIC.condition_hero
    local tagv_max = BASIC.robot_condition_hero or {5, 11, 2, 2}
    for i, tag in ipairs(tag_type) do
        local max = tagv_max[i]
        local val = math.random(1, max)
        hero[tag] = val
    end
    local general_skill = GENERAL_SKILLS[math.random(#GENERAL_SKILLS)]
    local skilllist = {general_skill}
    local t = {}
    local cnt = 0
    while cnt < 4 do
        local idx = math.random(#NORMAL_SKILLS)
        if not t[idx] then
            t[idx] = true
            cnt = cnt + 1
        end
    end
    for idx in pairs(t) do
        local list = NORMAL_SKILLS[idx]
        table.insert(skilllist, list[math.random(#list)])
    end
    hero.skilllist = skilllist

    local idx = math.random(#COMBO_SKILLS)
    local list = COMBO_SKILLS[idx]
    hero.combo_skill = list[math.random(#list)]

    -- 被动技能
    local passive_list = {}
    cnt = 0
    while cnt < 5 do
        local i = math.random(#PASSIVE_IDS)
        table.insert(passive_list, PASSIVE_IDS[i])
        cnt = cnt + 1
    end
    hero.passive_list = passive_list

    local attrs = {}
    for k, v in pairs(ATTRIBUTE) do
        local val = math.random(v.max[1], v.max[2])
        attrs[k] = val
    end
    hero.baseattrs = attrs
    return hero
end

local function battle_start(self)
    local ctx = {
        ["multi_speed"] = 3,
        ["mapid"] = 1005,
        ["nm"] = 'robot',
        ["auto"] = true,
        ["limit"] = 0,
        -- ["nostop_all"] = true,
        -- skip = true,
        -- dump = true,
        -- verify = true,
        save = true
    }
    local left, right = {}, {}
    for i = 1, 5 do
        local hero = rand_hero2(i)
        table.insert(left, hero)
        local mon = rand_hero2(i)
        table.insert(right, mon)
    end
    net.request(self, nil, 'battle_test',
        {ctx = ctx, left = left, right = right})
    net.request(self, nil, "battle_real_start", {})
    return ctx
end

local inwait = {}
function _M.wait(co, ti)
    assert(not inwait[co])
    local tid = timer.add(ti, function()
        _M.wakeup(co, false, "timeout")
    end)
    inwait[co] = true
    skynet.wait(co)
    local args = inwait[co]
    inwait[co] = nil
    timer.del(tid)
    return table.unpack(args)
end

function _M.wakeup(co, ok, ...)
    if inwait[co] == true then
        inwait[co] = {ok, ...}
        skynet.wakeup(co)
    end
end

function _H.skill_start_cast(self, msg)
    if msg.timestop and not msg.skip then
        local skillid = msg.skillid
        local cfg = SKILL_CFG[skillid]
        _M.wait(self, cfg.casttime)
        net.request(self, nil, "battle_pause", {pause = false})
    end
end

function _H.battle_end(self, msg)
    _M.wakeup(self.__co__, true, "battle_end")
end

function _M.onlogin(self)
    chat(self, "lua@robot_battle_test_load()")
    -- while true do
    local co = battle_start(self)
    self.__co__ = co
    local autoclear<close> = setmetatable({}, {
        __close = function()
            self.__co__ = nil
        end
    })
    local ok, f = _M.wait(co, 100000)
    assert(ok, f)
    -- end
end

return _M

