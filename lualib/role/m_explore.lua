local skynet = require "skynet"
local map = require "role.map"
local hinit = require "hero"
local cfgproxy = require "cfg.proxy"
local hattrs = require "hero.attrs"
local iface = require "battleiface"
local uattrs = require "util.attrs"
local herobest = require "hero.best"
local hero_passive = require "hero.passive"
local m_battle = require "role.m_battle"

local _LUA = require "handler.lua"

local query_cfg_byid = hinit.query_cfg_byid

local BASIC
skynet.init(function()
    BASIC = cfgproxy("basic")
end)

local insert = table.insert
local sort = table.sort

local _M = {}

local NM<const> = "explore"
local owner

function _M.start(self, ctx, cb)
    local owr = assert(ctx.owner)
    assert(ctx.mapid)

    if owr ~= owner or ctx.new then _M.over(self) end

    ctx.collection = NM
    map.start(self, ctx, cb)
    owner = owr
end

function _M.over(self)
    if not owner then return end
    map.over(self)
    owner = nil
end

local function calc_lineup_pool(self, temp_heroes, dead_heroes)
    local all = hinit.query_all(self)
    local pool = {}
    for uuid, v in pairs(all) do
        if not dead_heroes[uuid] then
            local attrs, zdl = hattrs.query(self, uuid)
            insert(pool, {
                uuid = uuid,
                id = v.id,
                level = v.level,
                attrs = attrs,
                zdl = zdl,
                passive_list = hero_passive.get(self, uuid)
            })
        end
    end
    for uuid, v in pairs(temp_heroes) do
        if not dead_heroes[uuid] then
            v.zdl = uattrs.zdl(v.attrs)
            insert(pool, v)
        end
    end
    sort(pool, function(a, b)
        return a.zdl > b.zdl
    end)
    return pool
end

function _LUA.explore_query_heroes(self, feature)
    return hinit.explore_query_heroes(self, feature)
end

function _LUA.explore_level_top5_average(self)
    return herobest.level_top5_average(self)
end

function _LUA.explore_query_lineup_only(self, nm)
    return m_battle.query(self, nm), herobest.level_top5_average(self)
end

function _LUA.explore_query_lineup(self, nm, temp_heroes, dead_heroes)
    local lineup = m_battle.query(self, nm)
    local heroes, TAB, POS = {}, {}, {}
    for _, v in ipairs(lineup) do
        local uuid, pos = v.uuid, v.pos
        local id, attrs, passive_list
        local o = temp_heroes[uuid]
        if o then
            id = o.id
            attrs = o.attrs
            passive_list = o.passive_list
            temp_heroes[uuid] = nil
        else
            o = hinit.query(self, uuid)
            if o then
                id = o.id
                attrs = hattrs.query(self, uuid)
                passive_list = hero_passive.get(self, uuid)
            end
        end
        if id then
            local cfg = query_cfg_byid(self, id)
            if not dead_heroes[uuid] then
                insert(heroes, iface.hero(o, attrs, pos, passive_list))
                TAB[cfg.tab] = true
                POS[pos] = true
            end
        end
    end
    if #heroes >= BASIC.battlemax then return heroes end
    local pool = calc_lineup_pool(self, temp_heroes, dead_heroes)
    local i = 1
    for _, v in ipairs(BASIC.explore_force_format) do
        if not POS[v] then
            while pool[i] do
                local o = pool[i]
                local cfg = query_cfg_byid(self, o.id)
                i = i + 1
                local tab = cfg.tab
                if not TAB[tab] then
                    TAB[tab] = true
                    POS[v] = true
                    insert(heroes, iface.hero(o, o.attrs, v, o.passive_list))
                    break
                end
            end
            if #heroes >= BASIC.battlemax then return heroes end
        end
    end
    return heroes
end

function _M.deldata(list)
    map.deldata(NM, list)
end

return _M
