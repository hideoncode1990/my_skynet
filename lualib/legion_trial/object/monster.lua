local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local iface = require "battleiface"
local objtype = require "legion_trial.objtype"
local uaward = require "util.award"
local cache = require("legion_trial.cache")("monster")
local schema = require "mongo.schema"
cache.schema(schema.NOBJ())
local uniq = require "uniq.c"
local client = require "client"
local rdrop = require "role.drop"
local min = math.min
local max = math.max
local floor = math.floor
local random = math.random

local PERCENT_FACTOR<const> = 1000

local MON_POOL, MON_GROUP, MON_REWARD
skynet.init(function()
    MON_POOL, MON_GROUP, MON_REWARD = cfgproxy("legion_trial_monster_pool",
        "legion_trial_monster_group", "legion_trial_monster_reward")
end)
local _M = {}

function _M.enter(self)
    local C = cache.get(self)
    client.push(self, "legion_trial_objs", {objs = C})
    return C
end

local function rand_hero(pool)
    local pools = MON_POOL[pool]
    local w = random(pools[0])
    local weight = 0
    for _, p in ipairs(pools) do
        weight = weight + p.weight
        if w <= weight then return p.hero end
    end
end

local function get_cfg(mainline, groupid)
    local mon_groups = MON_GROUP[groupid]
    for _, cfg in ipairs(mon_groups) do
        if mainline >= cfg.mainline then return cfg end
    end
end

local function get_monster_reward(mainline, coes)
    for _, cfg in ipairs(MON_REWARD) do
        if mainline >= cfg.mainline then
            local reward = cfg.award
            local r = {}
            for i, v in ipairs(reward) do
                local coe = (coes[i] or 1000) / 1000
                local cnt = floor(v[3] * coe)
                table.insert(r, {v[1], v[2], cnt})
            end
            return r
        end
    end
end

local function new_monster(mainline, groupid)
    local cfg = assert(get_cfg(mainline, groupid))
    local monsters = {}
    for i, v in ipairs(cfg.monster) do
        local pos, pool, lv_min, lv_max, boss = table.unpack(v)
        local heroid = assert(rand_hero(pool))
        local lv = random(lv_min, lv_max)
        table.insert(monsters, {
            base = {pos, heroid, lv, boss},
            hp_percent = PERCENT_FACTOR,
            tpv_percent = 0,
            zdl = iface.mon_zdl(heroid, lv, cfg.attrs[i], cfg.attrs_extra)
        })
    end
    return monsters
end

function _M.new(self, pos, objid, groupid, pass, reward_coe, fixex_award, dropid)
    local mainline = self.mainline
    local monsters = new_monster(mainline, groupid)
    local C = cache.get(self)
    local uuid = uniq.uuid()
    local reward1, reward2, reward3
    if reward_coe then reward1 = get_monster_reward(mainline, reward_coe) end
    if fixex_award then reward2 = fixex_award end
    if dropid then reward3 = rdrop.calc(dropid) end
    local adds = uaward().append(reward1, reward2, reward3)
    local obj = {
        type = objtype.monster,
        uuid = uuid,
        pos = pos,
        objid = objid,
        groupid = groupid,
        mainline = mainline,
        monsters = monsters,
        reward = adds.result,
        pass = pass,
        award = adds.pack()
    }
    C[uuid] = obj
    cache.dirty(self)
    return obj
end

function _M.attr_change(self, uuid, last_attrs)
    local C = cache.get(self)
    local obj = C[uuid]
    for _, mon in ipairs(obj.monsters) do
        local pos = mon.base[1]
        local attr = last_attrs[pos]
        if attr then
            local hp_p = 0
            if attr.hp > 0 then
                hp_p = max(1, floor(attr.hp / attr.hpmax * PERCENT_FACTOR))
            end
            mon.hp_percent = min(PERCENT_FACTOR, hp_p)
            local tpv_p = 0
            if attr.tpv > 0 then
                tpv_p = max(1, floor(attr.tpv / attr.tpvmax * PERCENT_FACTOR))
            end
            mon.tpv_percent = min(PERCENT_FACTOR, tpv_p)
        end
    end
    cache.dirty(self)
    client.push(self, "legion_trial_objs", {objs = {[uuid] = obj}})
end

function _M.create_monsters(self, uuid)
    local C = cache.get(self)
    local obj = assert(C[uuid])
    local heroes = {}
    local bossid
    local cfg = get_cfg(obj.mainline, obj.groupid)
    local effectlist = cfg.effect or {}
    for i, mon in ipairs(obj.monsters) do
        local hp_percent = mon.hp_percent
        if hp_percent ~= 0 then
            local heroid, isboss = mon.base[2], mon.base[4]
            if isboss then bossid = heroid end
            local monster = iface.monster(mon.base, cfg.attrs[i],
                cfg.attrs_extra, effectlist[i])

            local tpv_percent = mon.tpv_percent
            local hpmax, tpvmax = monster.baseattrs.hpmax,
                monster.baseattrs.tpvmax
            monster.lasthp = hp_percent and
                                 min(hpmax, max(1, floor(
                    hp_percent / PERCENT_FACTOR * hpmax)))
            monster.lasttpv = tpv_percent and
                                  min(tpvmax, floor(
                    tpv_percent / PERCENT_FACTOR * tpvmax))
            table.insert(heroes, monster)
        end
    end
    return {heroes = heroes, player = {bossid = bossid}}
end

function _M.del(self, uuid)
    local C = cache.get(self)
    C[uuid] = nil
    cache.dirty(self)
end

function _M.clean(self)
    cache.clean(self)
end

function _M.dirty(self)
    cache.dirty(self)
end
return _M
