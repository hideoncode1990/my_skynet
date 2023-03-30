-- 专属武器exclusive
local skynet = require "skynet"
local client = require "client.mods"
local hattrs = require "hero.attrs"
local cfgproxy = require "cfg.proxy"
local award = require "role.award"
local uaward = require "util.award"
local uattrs = require "util.attrs"
local event = require "role.event"
local hinit = require "hero"
local flowlog = require "flowlog"
local umath = require "util.math"
local cache = require("mongo.role")("exclusive")
local hero_passive = require "hero.passive"
local schema = require "mongo.schema"
local task = require "task"

local _H = require "handler.client"

cache.schema(schema.SAR())

local append = uattrs.append
local insert = table.insert

local NM<const> = "exclusive"

local CFG, CFG_LV

skynet.init(function()
    CFG, CFG_LV = cfgproxy("exclusive", "exclusive_level")
end)

require("hero.mod").reg {
    name = NM,
    init = function(self, uuid, obj)
        obj.exclusive = cache.get(self)[uuid]
    end,
    remove = function(self, uuid)
        local C = cache.get(self)
        if C[uuid] then
            C[uuid] = nil
            cache.dirty(self)
            hero_passive.del(self, uuid)
        end
    end
}

local function getcfg(self, uuid)
    local cfg_hero = hinit.query_cfg(self, uuid)
    return CFG[cfg_hero.exclusive], cfg_hero.feature
end

local function calc_cost(_, feature, begin, over)
    local ret = {}
    local field = "cost_" .. feature
    for i = begin, over do insert(ret, CFG_LV[i][field]) end
    return uaward().append(ret).result
end

function _H.exclusive_levelup(self, msg)
    local uuid, tarlv = msg.uuid, msg.tarlv
    local C = cache.get(self)
    local level = C[uuid]
    if not level then return {e = 1} end
    if tarlv <= level then return {e = 2} end

    local cfg, feature = getcfg(self, uuid)
    if tarlv > cfg.maxlevel then return {e = 3} end

    local option = {flag = "exclusive_levelup", arg1 = uuid, arg2 = tarlv}
    if not award.del(self, option, calc_cost(self, feature, level + 1, tarlv)) then
        return {e = 4}
    end

    C[uuid] = tarlv
    cache.dirty(self)

    hinit.query(self, uuid).exclusive = tarlv
    hattrs.dirty(self, NM, uuid)
    hero_passive.dirty(self, NM, uuid)

    task.trigger(self, "exclusive", tarlv)
    flowlog.role_act(self, option)
    return {e = 0}
end

event.reg("EV_HERO_STAGEUP", NM, function(self, uuid2id)
    local C = cache.get(self)
    local change = {}
    for uuid, id in pairs(uuid2id) do
        local cfg = hinit.query_cfg_byid(self, id)
        if not C[uuid] and cfg.exclusive then
            local level = 0
            C[uuid] = level
            hinit.query(self, uuid).exclusive = level
            insert(change, {uuid = uuid, level = level})
        end
    end
    if next(change) then
        cache.dirty(self)
        for _, v in ipairs(change) do
            hattrs.dirty(self, NM, v.uuid)
            hero_passive.dirty(self, NM, v.uuid)
        end
        client.push(self, "hero", "exclusive_open_list", {list = change})
    end
end)

hattrs.reg(NM, function(self, uuid)
    local level = cache.get(self)[uuid]
    if not level or level == 0 then return {} end
    local cfg = getcfg(self, uuid)

    local fixd_attrs = {}
    for _, v in ipairs(cfg.fixed_attrs) do fixd_attrs[v[1]] = v[2] end

    local coe = CFG_LV[level].growup / 1000
    local growup_attrs = {}
    for _, v in ipairs(cfg.growup_attrs) do growup_attrs[v[1]] = v[2] * coe end
    return append(fixd_attrs, growup_attrs)
end)

hero_passive.reg(NM, function(self, uuid)
    local level = cache.get(self)[uuid]
    if not level or level == 0 then return end

    local cfg_effect = getcfg(self, uuid).effect
    for i = #cfg_effect, 1, -1 do
        local the_effect = cfg_effect[i]
        if level >= the_effect[1] then
            return {table.unpack(the_effect, 2)}
        end
    end
end)
