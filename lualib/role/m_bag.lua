local skynet = require "skynet"
local client = require "client.mods"
local cfgproxy = require "cfg.proxy"
local award = require "role.award"
local awardtype = require "role.award.type"
local schema = require "mongo.schema"
local cache = require("mongo.role")("items")
local flowlog = require "flowlog"

cache.schema(schema.NOBJ())

local insert = table.insert

local NM<const> = "items"

local _M = {}

local CFG
skynet.init(function()
    CFG = cfgproxy("item")
end)

require("role.mods") {
    name = NM,
    load = cache.get,
    enter = function(self)
        client.enter(self, NM, "items_all", {list = cache.get(self)})
    end
}

local function add(self, nms, pkts, option, items)
    local C = cache.get(self)
    nms.items_add = NM
    for _, cfg in ipairs(items) do
        local id, cnt = cfg[2], cfg[3]

        assert(CFG[id] and cnt > 0)
        local prev = C[id] or 0
        local last = prev + cnt
        C[id] = last
        flowlog.platlog(self, NM, {
            opt = "add",
            flag = option.flag,
            arg1 = option.arg1,
            arg2 = option.arg2,
            id = id,
            prevplat = prev,
            prev = prev,
            last = last,
            change = cnt
        }, "item", {action = 1, tp = awardtype.items})
        insert(pkts.items_add, {change = cnt, last = last, id = id})
    end
    cache.dirty(self)
    return true
end

local function del(self, nms, pkts, option, items)
    local C = cache.get(self)
    nms.items_del = NM
    for _, cfg in ipairs(items) do
        local id, cnt = cfg[2], cfg[3]

        assert(CFG[id] and cnt > 0)
        local prev = C[id] or 0
        local last = prev - cnt
        assert(last >= 0)
        if last == 0 then
            C[id] = nil
        else
            C[id] = last
        end
        flowlog.platlog(self, NM, {
            opt = "del",
            flag = option.flag,
            arg1 = option.arg1,
            arg2 = option.arg2,
            id = id,
            prev = prev,
            last = last,
            change = cnt
        }, "item", {action = -1, tp = awardtype.items, id = id})
        insert(pkts.items_del, {change = -cnt, last = last, id = id})
    end
    cache.dirty(self)
    return true
end

local function checkadd(self, items)
    local C = cache.get(self)
    local cnts = {}
    for _, cfg in ipairs(items) do
        local id, cnt = cfg[2], cfg[3]
        cnts[id] = (cnts[id] or 0) + cnt
    end
    for id, cnt in pairs(cnts) do
        local cfg_item = CFG[id]
        local cnt_max = cfg_item.cnt_max
        assert(cnt > 0)
        local prev = C[id] or 0
        local last = prev + cnt
        if cnt_max and last > cnt_max then return false, id end
    end
    return true
end

local function checkdel(self, items)
    local C = cache.get(self)
    local cnts = {}
    for _, cfg in ipairs(items) do
        local id, cnt = cfg[2], cfg[3]
        cnts[id] = (cnts[id] or 0) + cnt
    end
    for id, cnt in pairs(cnts) do
        if (C[id] or 0) < cnt then return false, id end
    end
    return true
end

local function getcnt(self, id)
    return cache.get(self)[id] or 0
end

award.reg {
    type = awardtype.items,
    add = add,
    checkadd = checkadd,
    del = del,
    checkdel = checkdel,
    getcnt = getcnt
}

function _M.query_cfg(_, id)
    return CFG[id]
end

return _M
