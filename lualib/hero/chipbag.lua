local skynet = require "skynet"
local client = require "client.mods"
local cfgproxy = require "cfg.proxy"
local awardtype = require "role.award.type"
local award = require "role.award"
local cache = require("mongo.role")("chips")
local flowlog = require "flowlog"
local schema = require "mongo.schema"

local _M = {}

cache.schema(schema.SAR())

local insert = table.insert

local NM<const> = "chipbag"

local CHIPCNT, BASIC, CFG = 0, nil, nil
skynet.init(function()
    BASIC, CFG = cfgproxy("basic", "chip")
end)

require("hero.mod").reg {
    name = NM,
    load = function(self)
        for _, cnt in pairs(cache.get(self)) do CHIPCNT = CHIPCNT + cnt end
    end,
    enter = function(self)
        client.enter(self, NM, "chipbag_list", {list = cache.get(self)})
    end
}

local function isfull(_, n)
    return CHIPCNT + (n or 1) > BASIC.chip_max
end

local function add_inner(self, C, id, cnt, option, pushtab)
    assert(CFG[id] and cnt > 0)
    local prev = C[id] or 0
    local last = prev + cnt
    C[id] = last
    CHIPCNT = CHIPCNT + cnt
    insert(pushtab, {change = cnt, last = last, id = id})
    flowlog.platlog(self, NM, {
        opt = "add",
        flag = option.flag,
        arg1 = option.arg1,
        arg2 = option.arg2,
        id = id,
        prev = prev,
        last = last,
        change = cnt
    }, "item", {action = 1, tp = awardtype.chip})
end

local function add(self, nms, pkts, option, items)
    local C = cache.get(self)
    nms.chipbag_add = NM
    for _, item in ipairs(items) do
        local id, cnt = item[2], item[3]
        add_inner(self, C, id, cnt, option, pkts.chipbag_add)
    end
    cache.dirty(self)
    return true
end

function _M.add(self, cnts, option)
    local C = cache.get(self)
    local chipbag_add = {}
    for id, cnt in pairs(cnts) do
        add_inner(self, C, id, cnt, option, chipbag_add)
    end
    cache.dirty(self)
    client.push(self, NM, "chipbag_add",
        {list = chipbag_add, args = option.flag})
    return true
end

local function del_inner(self, C, id, cnt, option, pushtab)
    assert(CFG[id] and cnt > 0)
    local prev = C[id] or 0
    local last = prev - cnt
    assert(last >= 0)
    if last == 0 then
        C[id] = nil
    else
        C[id] = last
    end
    CHIPCNT = CHIPCNT - cnt
    insert(pushtab, {change = cnt, last = last, id = id})

    flowlog.platlog(self, NM, {
        opt = "del",
        flag = option.flag,
        arg1 = option.arg1,
        arg2 = option.arg2,
        id = id,
        prev = prev,
        last = last,
        change = cnt
    }, "item", {action = -1, tp = awardtype.chip})
end

local function del(self, nms, pkts, option, items)
    local C = cache.get(self)
    nms.chipbag_del = NM
    for _, cfg in ipairs(items) do
        local id, cnt = cfg[2], cfg[3]
        del_inner(self, C, id, cnt, option, pkts.chipbag_del)
    end
    cache.dirty(self)
    return true
end

function _M.del(self, cnts, option) -- 用于穿芯片
    local C = cache.get(self)
    local pushtab = {}
    for id, cnt in pairs(cnts) do
        del_inner(self, C, id, cnt, option, pushtab)
    end
    cache.dirty(self)
    client.push(self, NM, "chipbag_del", {list = pushtab, args = option.flag})
    return true
end

local function checkadd(self, items)
    local n = 0
    for _, item in ipairs(items) do
        local id, cnt = item[2], item[3]
        assert(CFG[id] and cnt > 0)
        n = n + cnt
    end
    return not isfull(self, n)
end

local function checkdel(self, items)
    local C = cache.get(self)
    local cnts = {}
    for _, item in ipairs(items) do
        local id, cnt = item[2], item[3]
        cnts[id] = (cnts[id] or 0) + cnt
    end
    for id, cnt in pairs(cnts) do
        if (C[id] or 0) < cnt then return false, id end
    end
    return true
end

function _M.checkdel(self, cnts)
    local C = cache.get(self)
    for id, cnt in pairs(cnts) do if (C[id] or 0) < cnt then return false end end
    return true
end

local function getcnt(self, id)
    return cache.get(self)[id] or 0
end

award.reg {
    type = awardtype.chip,
    add = add,
    checkadd = checkadd,
    del = del,
    checkdel = checkdel,
    getcnt = getcnt
}

function _M.chipcfg(_, id)
    return CFG[id]
end

_M.checkadd = checkadd
_M.getcnt = getcnt
_M.isfull = isfull

return _M
