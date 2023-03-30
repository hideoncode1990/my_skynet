local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local client = require "client.mods"
local hero = require "hero"
local fnopen = require "role.fnopen"
local heroattrs = require "hero.attrs"
local herosync = require "hero.sync"
local award = require "role.award"
local flowlog = require "flowlog"
local herobest = require "hero.best"
local event = require "role.event"
local task = require "task"

local uattrs = require "util.attrs"
local uaward = require "util.award"

local _H = require "handler.client"

local CFG_LV, MCFG, BASIC
skynet.init(function()
    CFG_LV, MCFG, BASIC = cfgproxy("hero_level", "hero_monster", "basic")
end)

local function query_coe(id, level)
    local stage = MCFG[id].stage
    return CFG_LV[level]["stage_" .. stage]
end

local NM<const> = "sync_level"

heroattrs.reg(NM, function(self, uuid)
    return uattrs.filter(hero.query_cfg(self, uuid))
end)

heroattrs.regafter(NM, function(self, uuid, ret)
    local baseattr = heroattrs.mod(self, uuid, NM)
    local obj = hero.query(self, uuid)
    local coe = query_coe(obj.id, obj.level)
    uattrs.hero_attrs(ret, baseattr, coe)
end)

local function level_init(self, uuid, obj)
    obj = obj or hero.query(self, uuid)
    local level = obj.lvreal
    if herosync.check(self, uuid) then
        local cfg = hero.query_cfg_byid(self, obj.id)
        level = math.min(herobest.level(self), cfg.limit_level)
    end
    obj.level = level
end

local function level_change(self, uuid, obj)
    obj = obj or hero.query(self, uuid)
    local level = obj.lvreal

    if herosync.check(self, uuid) then
        local cfg = hero.query_cfg_byid(self, obj.id)
        level = math.min(herobest.level(self), cfg.limit_level)
    end
    local old_level = obj.level
    if level ~= old_level then
        obj.level = level
        heroattrs.dirty(self, "sync_level", uuid)
        client.push(self, "hero", "hero_level_change",
            {uuid = uuid, level = level})
        event.occur("EV_HERO_LVUP", self, uuid, level, old_level)
        task.trigger(self, "hero_level", level)
    end
end

event.reg("EV_HERO_SYNCCHG", "level_sync", function(self, uuid)
    local obj = hero.query(self, uuid)

    if obj then level_change(self, uuid, obj) end
end)

require("hero.mod").reg {
    name = "sync_level",
    load = function(self)
        local list = hero.query_all(self)
        herobest.init(self, list)
        for uuid, obj in pairs(list) do level_init(self, uuid, obj) end
    end,
    loaded = function(self)
        herobest.try_build(self)
    end,
    create = function(self, uuid)
        local obj = hero.query(self, uuid)
        level_init(self, uuid, obj)
        skynet.fork(herobest.add, self, obj)
    end,
    levelup = function(self, uuid)
        level_change(self, uuid)
        skynet.fork(herobest.update, self, "levelup")
    end,
    reset = function(self, uuid)
        level_change(self, uuid)
        skynet.fork(herobest.update, self, "reset")
    end,
    inherit = function(self, uuid, obj)
        level_init(self, uuid, obj)
    end,
    remove = function(self, uuid)
        herobest.remove(self, uuid)
        herosync.remove_notime(self, {[uuid] = true})
    end,
    enter = function(self)
        herobest.enter(self)
    end
}

local function calc_cost(now_lv, tar_lv)
    local ctx = uaward()
    for i = now_lv, tar_lv - 1 do ctx.append(CFG_LV[i].consume) end
    return ctx.result
end

local function get_lvlimit(now_lv, tar_lv)
    local lvlimit
    for i = now_lv + 1, tar_lv do
        local sync_level = CFG_LV[i].sync_level
        if sync_level then lvlimit = math.max(sync_level, lvlimit or 0) end
    end
    return lvlimit
end

function _H.hero_levelup(self, msg)
    local uuid, tar_lv = msg.uuid, msg.tar_lv
    local obj = hero.query(self, uuid)
    if not obj then return {e = 1} end

    if herosync.build(self) then return {e = 3} end
    if herosync.check(self, uuid) then return {e = 3} end

    local id, now_lv = obj.id, obj.lvreal
    tar_lv = tar_lv or now_lv + 1
    if tar_lv <= now_lv then return {e = 2} end

    local max_lv = hero.query_cfg_byid(self, id).maxlevel
    if tar_lv > max_lv then return {e = 3} end

    local lvlimit = get_lvlimit(now_lv, tar_lv)
    if lvlimit and herobest.level(self) < lvlimit then return {e = 5} end

    local cost = calc_cost(now_lv, tar_lv)
    local option = {flag = "hero_levelup", arg1 = uuid, arg2 = tar_lv}

    local ok, e = award.del(self, option, cost)
    if not ok then return {e = e} end

    local old_attrs = heroattrs.query(self, uuid)
    hero.levelup(self, uuid, tar_lv, option)
    local new_attrs = heroattrs.dirty_now(self, "base", uuid)
    flowlog.role_act(self, option)
    event.occur("EV_HERO_LVREAL_UP", self)
    task.trigger(self, "hero_levelup")
    task.trigger(self, {maintype = "hero_levelup_at", arg = tar_lv}, uuid)
    return {
        e = 0,
        uuid = uuid,
        lvreal = tar_lv,
        new_attrs = new_attrs,
        old_attrs = old_attrs
    }
end

function _H.herosync_add(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local uuid, pos = msg.uuid, msg.pos
    local obj = hero.query(self, uuid)
    if not obj then return {e = 2} end

    if herobest.check(self, uuid) then return {e = 3} end

    local ok, e = herosync.add(self, uuid, pos)
    if not ok then return {e = e} end
    return {e = 0}
end

function _H.herosync_remove(self, msg)
    local uuid, pos = msg.uuid, msg.pos
    local obj = hero.query(self, uuid)
    if not obj then return {e = 1} end

    local d = herosync.remove(self, uuid, pos)
    if not d then return {e = 2} end
    return {e = 0, optime = d.optime}
end

function _H.herosync_open(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local pos = msg.pos
    local ok, e = herosync.slot_open(self, pos)
    if not ok then return {e = e} end
    return {e = 0}
end

function _H.herosync_buy(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local pos = msg.pos
    local ok, e = herosync.slot_buy(self, pos)
    if not ok then return {e = e} end
    return {e = 0}
end

local function make_sort1(self)
    return function(l, r)
        local luuid, ruuid = l.uuid, r.uuid
        if luuid and ruuid then
            local lcfg, rcfg = hero.query_cfg(self, luuid),
                hero.query_cfg(self, ruuid)
            if lcfg.stage == rcfg.stage then
                local lobj, robj = hero.query(self, luuid),
                    hero.query(self, ruuid)
                return lobj.id > robj.id
            else
                return lcfg.feature < rcfg.feature
            end
        elseif luuid then
            return true
        elseif ruuid then
            return false
        else
            return l.optime < r.optime
        end
    end
end

local function make_sort2(self)
    return function(l, r)
        local luuid, ruuid = l.uuid, r.uuid
        if luuid and ruuid then
            local lcfg, rcfg = hero.query_cfg(self, luuid),
                hero.query_cfg(self, ruuid)
            if lcfg.feature == rcfg.feature then
                return lcfg.stage > rcfg.stage
            else
                return lcfg.feature < rcfg.feature
            end
        elseif luuid then
            return true
        elseif ruuid then
            return false
        else
            return l.optime < r.optime
        end
    end
end

local sort_method = {[1] = make_sort1, [2] = make_sort2}

function _H.herosync_sort(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local type = msg.type
    herosync.sort(self, sort_method[type](self))
    return {e = 0}
end

function _H.herosync_build_levelup(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local level = msg.level
    if level > math.min(BASIC.herobest_build_level + BASIC.sync_build_lvpara *
                            hero.tabcnt_greater_samestage(self,
            BASIC.sync_maxstage), BASIC.sync_build_lvlimit) then
        return {e = 5}
    end
    local ok, e = herosync.build_levelup(self, level)
    if not ok then return {e = e} end
    task.trigger(self, "hero_levelup")
    return {e = 0}
end

function _H.herosync_cleancd(self, msg)
    local pos = msg.pos
    local ok, e = herosync.cleancd(self, pos)
    if not ok then return {e = e} end
    return {e = 0}
end
