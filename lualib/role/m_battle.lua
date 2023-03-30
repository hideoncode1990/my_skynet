local skynet = require "skynet"
local client = require "client"
local fnopen = require "role.fnopen"
local hinit = require "hero"
local cfgproxy = require "cfg.proxy"
local iface = require "battleiface"
local hattrs = require "hero.attrs"
local passive = require "role.passive"
local utable = require "util.table"
local herobest = require "hero.best"
local reference = require "reference.server"
local hero_passive = require "hero.passive"
local cache = require("mongo.role")("battle")
local battle_check = require "battle.checks"
local battle = require "battle"

local _H = require "handler.client"
local _LUA = require "handler.lua"

local pairs = pairs
local table = table

local MON_CFG, BASIC
local _M = {}

local battle_ctx

skynet.init(function()
    MON_CFG, BASIC = cfgproxy("battlemon", "basic")
end)

local function push_setting(self)
    client.push(self, "battle_setting", {setting = cache.get(self)})
end

local function battle_skip(self)
    if battle_ctx then
        skynet.call(battle_ctx.battled, "lua", "battle_offline", self.rid)
        local co = battle_ctx
        if co then skynet.wait(co) end
    end
end

require("role.mods") {
    name = "battle",
    enter = function(self)
        battle_skip(self)
        push_setting(self)
    end,
    leave = battle_skip
}

local function get_cache(self, mod_name)
    local C = cache.get(self)
    local data = C[mod_name]
    if not data then
        data = {mod_name = mod_name}
        C[mod_name] = data
    end
    return data
end

local function check_accelerate(self, multi_speed)
    local nm = "accelerate_" .. (multi_speed or 1)
    return fnopen.check_open(self, nm)
end

function _M.set_lineup(self, mod_name, lineup, ismulti)
    local data = get_cache(self, mod_name)
    if ismulti then
        data.multi_list = battle.multi_pack(lineup)
    else
        data.list = lineup
    end
    cache.dirty(self)
end

function _M.query(self, mod_name)
    local C = cache.get(self)
    local data = C[mod_name] or {}
    return data.list or {}
end

function _M.check_lineup(self, lineup, havemap)
    if #lineup > BASIC.battlemax then return false, 108 end
    if #lineup == 0 then return false, 110 end
    local list, list_save = {}, {}
    local level_top5
    for k, v in ipairs(lineup) do
        local uuid, tab, attrs, zdl, passive_list = v.uuid, nil, nil, nil, nil
        local hero = hinit.query(self, uuid)
        if hero then -- 真英雄
            local hero_cfg = hinit.query_cfg_byid(self, hero.id)
            tab = hero_cfg.tab
            attrs, zdl = hattrs.query(self, uuid)
            passive_list = hero_passive.get(self, uuid)
        else
            -- 临时英雄的等级为等级最高的前五个的平均等级
            if not level_top5 then
                level_top5 = herobest.level_top5_average(self)
            end
            local level = level_top5
            -- 没有id, 无法算attrs
            hero = {level = level, uuid = uuid}
        end
        -- 临时英雄或错误uuid, 暂不能确定
        if not havemap and not hero then return false, 103 end
        list[k] = {
            uuid = uuid,
            pos = v.pos,
            tab = tab,
            attrs = attrs,
            zdl = zdl,
            obj = hero,
            passive_list = passive_list
        }
        list_save[k] = {uuid = uuid, pos = v.pos}
    end
    return list, list_save
end

-- 用于在agent中检测客户端传来的bi里面的 list 和multi_speed 字段
-- 不包括auto字段
function _M.check_bi(self, bi, havemap)
    if not check_accelerate(self, bi.multi_speed) then bi.multi_speed = 1 end
    return _M.check_lineup(self, bi.list, havemap)
end

function _M.check_feature(self, lineup, feature)
    if feature == 0 then return true end
    for _, v in ipairs(lineup) do
        local hero_cfg = hinit.query_cfg(self, v.uuid)
        if hero_cfg.feature ~= feature then return false end
    end
    return true
end

function _M.check(self)
    return battle_ctx
end

local function check_battle(check_name, b)
    if not battle_ctx then return false end
    local limit = battle_ctx.limit
    return battle_check.check(limit, check_name, b)
end

function _M.create_heroes(self, list, checktab)
    local heroes, check = {}, checktab or {}
    for _, info in ipairs(list) do
        local tab = info.tab
        if check[tab] then return false, 104 end
        check[tab] = true
        local hero = iface.hero(info.obj, info.attrs, info.pos,
            info.passive_list)
        table.insert(heroes, hero)
    end
    return {
        heroes = heroes,
        player = {rname = self.rname, level = self.level, zdl = self.zdl},
        passive_list = utable.copy(passive.get(self))
    }
end

function _M.create_monsters(cfg)
    local moncfg = MON_CFG[cfg]
    local monsters = {}
    local bossid
    local attrs_extra = moncfg.attrs_extra
    for i, _cfg in pairs(moncfg.hero) do
        local effect = moncfg.effect and moncfg.effect[i]
        table.insert(monsters,
            iface.monster(_cfg, moncfg.attrs[i], attrs_extra, effect))
        if _cfg[4] then bossid = _cfg[2] end
    end
    return {heroes = monsters, player = {bossid = bossid}}
end

function _H.battle_real_start(self)
    if not battle_ctx then return {e = 1} end
    skynet.send(battle_ctx.battled, "lua", "battle_real_start", self.rid)
    return {e = 0}
end

function _H.battle_terminate(self, msg)
    if not battle_ctx then return {e = 1} end
    if not check_battle("terminate") then return {e = 2} end

    skynet.send(battle_ctx.battled, "lua", "battle_terminate", self.rid,
        msg.restart)
    return {e = 0}
end

function _H.battle_accelerate(self, msg)
    if not battle_ctx then return {e = 1} end
    local multi_speed = msg.multi_speed
    if not check_accelerate(self, multi_speed) then return {e = 2} end
    skynet.send(battle_ctx.battled, "lua", "battle_accelerate", self.rid,
        multi_speed)
    return {e = 0, multi_speed = multi_speed}
end

function _H.battle_pause(self, msg)
    if not battle_ctx then return {e = 1} end
    local pause = msg.pause
    if pause then if not check_battle("pause") then return {e = 2} end end
    skynet.send(battle_ctx.battled, "lua", "battle_pause", self.rid, pause)
    return {e = 0, pause = pause}
end

function _H.battle_auto(self, msg)
    if not battle_ctx then return {e = 1} end
    local auto = msg.auto
    if not check_battle("auto", auto) then return {e = 2} end
    skynet.send(battle_ctx.battled, "lua", "battle_auto", self.rid, auto)
    return {e = 0, auto = auto}
end

function _H.battle_use_skill(self, msg)
    if not battle_ctx then return {e = 7} end
    if not check_battle("manual") then return {e = 1} end
    local id = msg.id
    local e = skynet.call(battle_ctx.battled, "lua", "use_skill", self.rid, id)
    return {e = e, id = id}
end

function _H.battle_skip(self, msg)
    -- if not check_battle("") then return {e = 1} end
end

function _LUA.battle_join(self, battled, limit)
    if battle_ctx then return end
    battle_ctx = {battled = battled, limit = limit}
    return reference.ref()
end

local replaylib = require "replay"
function _LUA.battle_replay(self, uuid)
    local obj = {rid = self.rid, fd = self.fd, addr = skynet.self()}
    replaylib.play(uuid, obj)
end

function _LUA.battle_release()
    local co
    co, battle_ctx = battle_ctx, nil
    skynet.wakeup(co)
    reference.unref()
end

return _M
