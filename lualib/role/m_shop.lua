local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local client = require "client"
local cache = require("mongo.role")("shops")
local utime = require "util.time"
local calendar = require "calendar"
local fnopen = require "role.fnopen"
local variable = require "variable"
local udrop = require "util.drop"
local award = require "role.award"
local flowlog = require "flowlog"
local cfgbase = require "cfg.base"
local schema = require "mongo.schema"
local task = require "task"
local event = require "role.event"
local lock = require("skynet.queue")()

local _H = require "handler.client"

local NM<const> = "shop"

local BASIC, CFG, CFG_GOODS, CFG_GROUP, CFG_RAN

local overtime = {}

cache.schema(schema.OBJ({
    version = schema.ORI,
    refresh_update = schema.ORI,
    shop = schema.NOBJ(schema.OBJ({
        update = schema.ORI,
        refreshed = schema.ORI,
        goods = schema.NOBJ()
    }))
}))

local function calc_start_time(offset)
    return utime.begin_day(variable.server_starttime) + offset
end

local function same_period(start, update, now, refresh_time)
    local n = (now - start) // refresh_time
    return update >= start + n * refresh_time and update < start + (n + 1) *
               refresh_time
end

local function ran_goods(groupid, _mainline)
    local cfg_ran = CFG_RAN[groupid]
    for k, tab in ipairs(cfg_ran.section) do
        if _mainline >= tab[1] and _mainline < tab[2] then -- 前闭后开
            return udrop.nexts(cfg_ran.pdf[k])
        end
    end
    assert(false)
end

local function check_refreshed(self)
    local C = cache.get(self)
    local now = utime.time_int()
    if not utime.same_day(now, C.refresh_update or 0) then
        C.refresh_update = now
        for _, v in pairs(cache.getsub(self, "shop")) do v.refreshed = 0 end
        cache.dirty(self)
    end
end

local function push_info(self)
    local sdata = cache.getsub(self, "shop")
    local ret = {}
    for num, info in pairs(sdata) do
        local _info = {}
        for index, v in pairs(info.goods) do
            _info[index] = {id = v.id, index = index, bought = v.bought}
        end
        ret[num] = {
            num = num,
            info = _info,
            over_time = overtime[num].over,
            update = info.update,
            refreshed = info.refreshed
        }
    end
    client.push(self, "shop_info", {list = ret})
end

local function get_cron(offset)
    local hour = offset // 3600
    offset = offset % 3600
    local min = offset // 60
    local sec = offset % 60
    return sec .. " " .. min .. " " .. hour .. " * * ?"
end

local function generate_goods(cfg_goods, _mainline)
    local goods = {}
    for index, groupid in pairs(cfg_goods) do
        goods[index] = {id = ran_goods(groupid, _mainline)}
    end
    return goods
end

local init_shop
local function init_inner(self, num, sdata, now, force, is_hotupdate)
    if not fnopen.check_open(self, NM .. num) then return end

    local cfg, cfg_goods = CFG[num], CFG_GOODS[num]
    local _mainline = self.mainline

    local data = sdata[num]
    if not data then
        data = {update = 0, refreshed = 0}
        sdata[num] = data
    end

    local start_time = calc_start_time(cfg.offset)
    local refresh_time = cfg.refresh_time * 86400
    if force or not same_period(start_time, data.update, now, refresh_time) then
        data.goods = generate_goods(cfg_goods, _mainline)
        data.update = now
        cache.dirty(self)
    else
        local goods, change = data.goods, nil
        for index, groupid in pairs(cfg_goods) do
            local info = goods[index]
            if not info or not CFG_GROUP[info.id] then
                change = true
                goods[index] = {id = ran_goods(groupid, _mainline)}
            end
        end
        if change then
            data.update = now
            cache.dirty(self)
        end
    end

    local over = now + refresh_time - (now - start_time) % refresh_time
    local overtbl = overtime[num]
    local cb = function()
        init_shop(self, num, sdata, utime.time_int())
        push_info(self)
    end

    if not overtbl then
        overtime[num] = {
            over = over,
            cb = calendar.subscribe(cb, get_cron(cfg.offset))
        }
    elseif is_hotupdate then
        calendar.unsubscribe(overtbl.cb)
        overtbl.cb = calendar.subscribe(cb, get_cron(cfg.offset))
    else
        overtime[num].over = over
    end
end

init_shop = function(self, num, sdata, now, force, is_hotupdate)
    lock(init_inner, self, num, sdata, now, force, is_hotupdate)
end

local function init(self, force, is_hotupdate)
    if not fnopen.check_open(self, NM) then return end

    local sdata = cache.getsub(self, "shop")
    local now = utime.time_int()
    for num in pairs(CFG) do
        init_shop(self, num, sdata, now, force, is_hotupdate)
    end
    return true
end

local function hotupdate_reg(self)
    cfgbase.onchange(function()
        init(self, false, true)
    end, "shop_list")
end

skynet.init(function()
    BASIC = cfgproxy("basic")

    local cfg_tbl = {"shop_list", "shop_goods", "shop_group", "shop_ran"}
    CFG, CFG_GOODS, CFG_GROUP, CFG_RAN = cfgproxy(table.unpack(cfg_tbl))
end)

local function init_version(self)
    cache.get(self).version = BASIC.shop_ver
    cache.dirty(self)
end

local function check_version(self)
    local C = cache.get(self)
    if C.version ~= BASIC.shop_ver then
        init(self, true)
        C.version = BASIC.shop_ver
        cache.dirty(self)
    end
end

skynet.init(function()
    fnopen.reg(NM, NM, function(self)
        init(self)
        init_version(self)
        push_info(self)
    end)

    for num in pairs(CFG) do
        local name = NM .. num
        fnopen.reg(name, name, function(self)
            init_shop(self, num, cache.getsub(self, "shop"), utime.time_int())
            push_info(self)
        end)
    end
end)

require("role.mods") {
    name = "shop",
    loaded = function(self)
        init(self)
        check_version(self)
        hotupdate_reg(self)
    end,
    enter = function(self)
        if not fnopen.check_open(self, NM) then return end
        check_refreshed(self)
        push_info(self)
    end,
    unload = function()
        for _, v in pairs(overtime) do
            calendar.unsubscribe(v.cb)
            v.cb = nil
        end
        overtime = nil
    end
}

function _H.shop_buy(self, msg)
    local num, index, update = msg.num, msg.index, msg.update
    if not fnopen.check_open(self, NM) then return {e = 1} end
    if not fnopen.check_open(self, "shop" .. num) then return {e = 2} end

    local sdata = cache.getsub(self, "shop")
    local info = sdata[num]
    local goods = info.goods

    local _goods = goods[index]
    if not _goods then return {e = 3} end

    if update ~= info.update then return {e = 6} end

    local id, bought = _goods.id, _goods.bought
    if bought then return {e = 4} end

    local item, price = CFG_GROUP[id].item, CFG_GROUP[id].price
    local option = {flag = "shop_buy", arg1 = num, arg2 = index}

    if not award.deladd(self, option, {price}, {item}) then return {e = 5} end

    _goods.bought = 1
    cache.dirty(self)

    local tasktype = CFG[num].tasktype
    if tasktype then task.trigger(self, tasktype) end

    flowlog.platlog(self, NM, {
        num = num,
        index = index,
        type = item[1],
        id = item[2],
        cnt = item[3]
    }, "shoptrade", {cost_money_id = price[1], cost_money_num = price[3]})
    return {e = 0}
end

function _H.shop_refresh(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local num, update = msg.num, msg.update
    if not fnopen.check_open(self, "shop" .. num) then return {e = 2} end
    local cfg = CFG[num]
    if not cfg then return {e = 3} end

    local sdata = cache.getsub(self, "shop")
    local info = sdata[num]
    if update ~= info.update then return {e = 6} end

    local refreshed = info.refreshed
    if refreshed >= cfg.refresh_max then return {e = 7} end

    local option = {flag = "shop_refresh", arg1 = num}
    if not award.del(self, option, {cfg.refresh_cost}) then return {e = 5} end

    refreshed = refreshed + 1
    info.refreshed = refreshed
    cache.dirty(self)

    info.goods = generate_goods(CFG_GOODS[num], self.mainline)
    info.update = utime.time_int()

    push_info(self)
    flowlog.role_act(self, option)
    return {e = 0, refreshed = refreshed}
end

event.reg("EV_UPDATE", NM, function(self)
    check_refreshed(self)
    push_info(self)
end)
