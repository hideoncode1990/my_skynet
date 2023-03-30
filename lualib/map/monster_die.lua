local skynet = require "skynet"
local utable = require "util.table"
local cfgproxy = require "cfg.proxy"
local map_attrs = require "map.attrs"
local iface = require "battleiface"
local cache = require("map.cache")("monster_die")
local schema = require "mongo.schema"

cache.schema(schema.NOBJ())

local _M = {}

local MON_CFG
skynet.init(function()
    MON_CFG = cfgproxy("battlemon")
end)

local DIE_CACHE = {}
local SPECIAL = {[1] = "tab", [2] = "feature"}

function _M.check(uuid)
    return cache.get()[uuid]
end

-- cfg[1]=tpid 类型编号
-- cfg[2]=uuid 怪物的uuid
-- cfg[3]  左边英雄中 需要满足条件的属性
-- cfg[4]=cnt  满足条件的个数
local function special_logic(arg)
    for _, cfg in ipairs(arg) do
        local uuid = cfg[2]
        local heroes = cache.get()[uuid]
        if not heroes then return end

        local tpid = cfg[1]
        local tpnm = SPECIAL[tpid]
        local key = tpnm .. uuid
        local subtab = utable.sub(DIE_CACHE, key)
        local val, count = cfg[3], cfg[4]
        local data = subtab[val]
        if not data then
            data = 0
            for _, hero in pairs(heroes) do
                if hero[tpnm] == val then data = data + 1 end
            end
            subtab[val] = data
        end
        if data < count then return false end
    end
    return true
end

-- para存在就执行普通死亡检测，若检测不过
-- arg存在就执行特殊死亡检测
function _M.logic(para, arg)
    return (para and utable.logic(cache.get(), para)) or
               (arg and special_logic(arg))
end

function _M.add(uuid, heroes)
    local C = cache.get()
    C[uuid] = heroes
    cache.dirty()
end

function _M.monster_create(o) -- last_attrs key=order
    if cache.get()[o.uuid] then return false, 2 end
    local monster = o.monster
    local cfg = MON_CFG[monster]
    local last_attrs = map_attrs.query_right(o.uuid)
    local monsters = {}
    local bossid
    local attrs = cfg.attrs
    local attrs_extra = cfg.attrs_extra
    local cfg_effect = cfg.effect

    for i, v in pairs(cfg.hero) do
        local pos = v[1]
        if v[4] then bossid = v[4] end
        local effect = cfg_effect and cfg_effect[i]
        local mon
        if last_attrs then
            local lattrs = last_attrs[pos]
            if lattrs then
                if lattrs.hp_percent ~= 0 then
                    mon = iface.monster(v, attrs[i], attrs_extra, effect)
                    mon.lasthp = map_attrs.per2val(mon.baseattrs.hpmax,
                        lattrs.hp_percent)
                    mon.lasttpv = map_attrs.per2val(mon.baseattrs.tpvmax,
                        lattrs.tpv_percent)
                end
            else
                mon = iface.monster(v, attrs[i], attrs_extra, effect)
            end
        else
            mon = iface.monster(v, attrs[i], attrs_extra, effect)
        end
        if mon then table.insert(monsters, mon) end
    end
    return monsters, bossid
end

return _M
