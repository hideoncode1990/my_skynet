local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local iface = require "battleiface"
local cache = require("legion_trial.cache")("battle_hero")
local schema = require "mongo.schema"
cache.schema(schema.OBJ({heroes = schema.NOBJ(), baghero_tpvfull = schema.ORI}))
local uniq = require "uniq.c"
local client = require "client"
local card = require "legion_trial.card"
local insert = table.insert
local getsub = require"util.table".getsub

local PERCENT_FACTOR<const> = 1000

local CFG, CFG_LEVEL, HERO_CFG
skynet.init(function()
    CFG, CFG_LEVEL, HERO_CFG = cfgproxy("herotower", "herotower_level", "hero")
end)
local _M = {}

function _M.enter(self)
    local C = cache.get(self)
    local heroes = C.heroes or {}
    local baghero_tpvfull = C.baghero_tpvfull
    if next(heroes) then
        local list, n = {}, 0
        for _, hero in pairs(heroes) do
            n = n + 1
            insert(list, hero)
            if n >= 100 then
                client.push(self, "legion_trial_heroes",
                    {heroes = list, baghero_tpvfull = baghero_tpvfull})
                list, n = {}, 0
            end
        end
        if next(list) then
            client.push(self, "legion_trial_heroes",
                {heroes = list, baghero_tpvfull = baghero_tpvfull})
        end
    end
end

function _M.add(self, target)
    local uuid = uniq.uuid()
    local o = {
        uuid = uuid,
        id = target.heroid,
        level = target.level,
        group = target.group,
        hp_percent = PERCENT_FACTOR,
        tpv_percent = 0,
        dummy = true
    }
    local heroes = cache.getsub(self, "heroes")
    heroes[uuid] = o
    cache.dirty(self)
    client.push(self, "legion_trial_heroes", {heroes = {[uuid] = o}})
    return o
end

local function mark_baghero_tpv(C, percent)
    local dirty
    local baghero_tpvfull = C.baghero_tpvfull or 0
    baghero_tpvfull = math.min(PERCENT_FACTOR, baghero_tpvfull + percent)
    if baghero_tpvfull ~= C.baghero_tpvfull then
        C.baghero_tpvfull = baghero_tpvfull
        dirty = true
    end
    return baghero_tpvfull, dirty
end

local function check_save(heroes, o, baghero_tpvfull)
    local uuid = o.uuid
    if not o.dummy then
        if baghero_tpvfull then
            if o.hp_percent ~= PERCENT_FACTOR or o.tpv_percent ~=
                baghero_tpvfull then
                heroes[uuid] = o
                return true
            end
        else
            if o.hp_percent ~= PERCENT_FACTOR or o.tpv_percent ~= 0 then
                heroes[uuid] = o
                return true
            end
        end
        heroes[uuid] = nil
        return true
    end
end

function _M.attr_changes(self, last_attrs)
    local losthp_add = card.passive_table("battle_end_recover", self)
    local changes = {}
    local C = cache.get(self)
    local heroes = getsub(C, "heroes")
    local baghero_tpvfull = C.baghero_tpvfull
    for uuid, hero in pairs(last_attrs) do
        local o = heroes[uuid] or
                      {uuid = uuid, cfgid = hero.cfgid, level = hero.level}
        local lasthp, lasttpv = hero.hp or 0, hero.tpv or 0
        local hpmax, tpvmax = hero.hpmax, hero.tpvmax
        if losthp_add > 0 then
            local losthp = math.max(0, hpmax - lasthp)
            local hp = math.floor(losthp * losthp_add / PERCENT_FACTOR)
            lasthp = lasthp + hp
        end
        o.hp_percent = math.min(PERCENT_FACTOR,
            math.floor(lasthp / hpmax * PERCENT_FACTOR))
        o.tpv_percent = math.min(PERCENT_FACTOR,
            math.floor(lasttpv / tpvmax * PERCENT_FACTOR))
        check_save(heroes, o, baghero_tpvfull)
        changes[uuid] = o
    end
    cache.dirty(self)
    client.push(self, "legion_trial_heroes", {heroes = changes})
end

function _M.recover(self, coe)
    local C = cache.get(self)
    local heroes = getsub(C, "heroes")
    local changes = {}
    local spring_add = 0 -- card.passive_table("spring_extra_recover",self)
    coe = math.floor(coe * (1 + spring_add / PERCENT_FACTOR))
    local baghero_tpvfull, dirty = mark_baghero_tpv(C, coe)
    for _, o in pairs(heroes) do
        local hp_percent, tpv_percent = o.hp_percent, o.tpv_percent
        if hp_percent > 0 then
            o.hp_percent = math.min(PERCENT_FACTOR, hp_percent + coe)
            o.tpv_percent = math.min(PERCENT_FACTOR, tpv_percent + coe)
            check_save(heroes, o, baghero_tpvfull)
            changes[o.uuid] = o
            dirty = true
        end
    end
    if dirty then
        cache.dirty(self)
        client.push(self, "legion_trial_heroes",
            {heroes = changes, baghero_tpvfull = baghero_tpvfull})
    end
end

function _M.revive(self, coe, cnt)
    coe = coe or PERCENT_FACTOR
    local C = cache.get(self)
    local heroes = getsub(C, "heroes")
    local baghero_tpvfull = C.baghero_tpvfull
    local list = {}
    for _, o in pairs(heroes) do
        local hp_percent = o.hp_percent
        if hp_percent == 0 then table.insert(list, o.uuid) end
    end
    if #list > 0 then
        cnt = cnt or #list
        local changes = {}
        while cnt > 0 and #list > 0 do
            cnt = cnt - 1
            local i = math.random(#list)
            local uuid = table.remove(list, i)
            local o = heroes[uuid]
            o.hp_percent = coe
            o.tpv_percent = coe
            check_save(heroes, o, baghero_tpvfull)
            changes[uuid] = o
        end

        if next(changes) then
            cache.dirty(self)
            client.push(self, "legion_trial_heroes", {heroes = changes})
        end
    end
end

function _M.all_hptpv_full(self)
    local C = cache.get(self)
    local heroes = getsub(C, "heroes")
    local baghero_tpvfull, dirty = mark_baghero_tpv(C, PERCENT_FACTOR)
    local changes = {}
    for uuid, o in pairs(heroes) do
        if o.hp_percent ~= PERCENT_FACTOR or o.tpv_percent ~= PERCENT_FACTOR then
            o.hp_percent = PERCENT_FACTOR
            o.tpv_percent = PERCENT_FACTOR
            check_save(heroes, o, baghero_tpvfull)
            changes[uuid] = o
            dirty = true
        end
    end
    if dirty then
        cache.dirty(self)
        client.push(self, "legion_trial_heroes",
            {heroes = changes, baghero_tpvfull = baghero_tpvfull})
    end
end

function _M.create_heroes(self, list)
    local heroes, check = {}, {}
    local C = cache.get(self)
    local C_heroes = C.heroes or {}
    local baghero_tpvfull = C.baghero_tpvfull
    for _, v in ipairs(list) do
        local uuid, tab = v.uuid, v.tab
        local o = C_heroes[uuid]
        if o and o.hp_percent == 0 then return false, 2 end
        local hero
        if tab then
            if check[tab] then return false, 3 end
            check[tab] = true
            hero = iface.hero(v.obj, v.attrs, v.pos, v.passive_list)
        else
            if not o then return false, 1 end
            tab = HERO_CFG[o.id].tab
            if check[tab] then return false, 3 end

            check[tab] = true
            local level = v.obj.level
            local cfg = CFG_LEVEL[level]
            local attrs = iface.temphero_attrs(o.id, level, cfg.attrs,
                cfg.attrs_extra)
            o.level = level
            hero = iface.hero(o, attrs, v.pos, CFG[o.group][o.id].effect)
        end

        local hp_percent = o and o.hp_percent
        local tpv_percent = o and o.tpv_percent or baghero_tpvfull
        local hpmax, tpvmax = hero.baseattrs.hpmax, hero.baseattrs.tpvmax
        hero.lasthp = hp_percent and
                          math.min(hpmax, math.max(1, math.floor(
                hp_percent / PERCENT_FACTOR * hpmax)))
        hero.lasttpv = tpv_percent and
                           math.min(tpvmax, math.floor(
                tpv_percent / PERCENT_FACTOR * tpvmax))
        table.insert(heroes, hero)
    end
    local left = {
        heroes = heroes,
        player = {rname = self.rname, level = self.level},
        passive_list = card.passive_list(self)
    }
    return left
end

function _M.clean(self)
    cache.clean(self)
end

return _M
