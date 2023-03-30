--[[
    没有uuid的物品的统一背包(不包含英雄、装备)
    需要缓存到ALL里面就在这里添加消息接口
--]] --
local utable = require "util.table"
local awardtype = require "role.award.type"
local log = require "robot.log"

local _H = require "handler.client"

local _M = {}

local ALL = {}

function _H.money_all(self, msg)
    local cnts = msg.cnts
    for k, tp in pairs(msg.types) do
        local cnt = cnts[k]
        ALL[tp] = {[0] = cnt}
    end
end

function _H.money_add(self, msg)
    for _, v in ipairs(msg.list) do
        local tp, change, last = v.type, v.change, v.last
        local subtab = utable.sub(ALL, tp)
        local cnt = subtab[0] or 0
        subtab[0] = last
        assert(last == change + cnt)
        log(self, {opt = "money_add", type = tp, cnt = last, change = change})
    end
end

function _H.money_del(self, msg)
    for _, v in ipairs(msg.list) do
        local tp, change, last = v.type, v.change, v.last
        local subtab = utable.sub(ALL, tp)
        local cnt = ALL[tp][0]
        subtab[0] = last
        assert(last == change + cnt)
        log(self, {opt = "money_del", type = tp, cnt = last, change = change})
    end
end

function _H.diamond_info(self, msg)
    ALL[awardtype.diamond] = {[0] = msg.bind}
    log(self, {
        opt = "diamond_info",
        type = awardtype.diamond,
        id = 0,
        cnt = msg.bind
    })
end

function _H.items_all(self, msg)
    local subtab = utable.sub(ALL, awardtype.items)
    for id, cnt in pairs(msg.list) do subtab[id] = cnt end
    log(self, {opt = "items_all"})
end

function _H.diamond_add(self, msg)
    for _, v in ipairs(msg.list) do
        local change, last = v.change, v.last
        local tp = awardtype.diamond
        local subtab = utable.sub(ALL, tp)
        local cnt = subtab[0] or 0
        subtab[0] = last
        assert(last == cnt + change)
        log(self, {opt = "diamond_add", last = last, change = change})
    end
end

function _H.diamond_del(self, msg)
    for _, v in ipairs(msg.list) do
        local change, last = v.change, v.last
        local tp = awardtype.diamond
        local subtab = utable.sub(ALL, tp)
        local cnt = ALL[tp][0]
        subtab[0] = last
        assert(last == cnt - change)
        log(self, {opt = "diamond_del", last = last, change = change})
    end
end

function _H.items_add(self, msg)
    for _, v in ipairs(msg.list) do
        local change, last, id = v.change, v.last, v.id
        local tp = awardtype.items
        local subtab = utable.sub(ALL, tp)
        local cnt = subtab[id] or 0
        subtab[id] = last
        assert(last == cnt + change)
        log(self, {opt = "items_add", last = last, change = change})
    end
end

function _H.items_del(self, msg)
    for _, v in ipairs(msg.list) do
        local change, last, id = v.change, v.last, v.id
        local tp = awardtype.items
        local subtab = utable.sub(ALL, tp)
        local cnt = subtab[id] or 0
        subtab[id] = last
        assert(last == cnt + change)
        log(self, {opt = "items_del", last = last, change = change})
    end
end

function _H.chipbag_list(self, msg)
    local subtab = utable.sub(ALL, awardtype.chip)
    for id, cnt in pairs(msg.list) do subtab[id] = cnt end
    log(self, {opt = "chipbag_list"})
end

function _H.chipbag_add(self, msg)
    for _, v in ipairs(msg.list) do
        local change, last, id = v.change, v.last, v.id
        local tp = awardtype.chip
        local subtab = utable.sub(ALL, tp)
        local cnt = subtab[id] or 0
        subtab[id] = last
        assert(last == cnt + change)
        log(self, {opt = "chipbag_add", last = last, change = change})
    end
end

function _H.chipbag_del(self, msg)
    for _, v in ipairs(msg.list) do
        local change, last, id = v.change, v.last, v.id
        local tp = awardtype.items
        local subtab = utable.sub(ALL, tp)
        local cnt = subtab[id] or 0
        subtab[id] = last
        assert(last == cnt - change)
        log(self, {opt = "chipbag_del", last = last, change = change})
    end
end

local cant_del = {
    hero = 6, -- 佣兵(英雄)
    equip = 7, -- 装备
    rexp = 8, -- 角色经验
    head = 9, -- 头像
    headframe = 10, -- 头像框
    vip_exp = 14 -- VIP经验
}

local function local_check(_, cost)
    local tp, id, cnt = cost[1], cost[2], cost[3]

    assert(not cant_del[tp])

    local subtab = ALL[tp]
    if not subtab then return false end
    local has_cnt = subtab[id] or 0
    if has_cnt >= cnt then
        return true
    else
        return false, tp, id, cnt, has_cnt
    end
end

function _M.checkdel_one(self, cost)
    return local_check(self, cost)
end

function _M.checkdel(self, costs)
    for _, v in ipairs(costs) do
        local ok, tp, id, cnt, has_cnt = local_check(self, v)
        if not ok then return false, tp, id, cnt, has_cnt end
    end
    return true
end

return _M
