local skynet = require "skynet"
local client = require "client.mods"
local cfgproxy = require "cfg.proxy"
local award = require "role.award"
local awardtype = require "role.award.type"
local flowlog = require "flowlog"
local roleinfo = require "roleinfo.change"
local event = require "role.event"

local _H = require "handler.client"

local schema = require "mongo.schema"
local cache = require("mongo.role")("heads")
cache.schema(schema.OBJ {
    heads = schema.SET(),
    headframes = schema.SET(),
    head_cur = schema.ORI,
    headframe_cur = schema.ORI
})

local insert = table.insert

local NM<const> = "head"
local _M = {}

local CFG_HEAD, CFG_HEADFRAME, CFG_TAB
skynet.init(function()
    CFG_HEAD, CFG_HEADFRAME, CFG_TAB =
        cfgproxy("head", "head_frame", "head_tab")
end)

local function packall(self)
    local heads, headframes = {0}, {0}
    for id in pairs(cache.getsub(self, "heads")) do insert(heads, id) end
    for id in pairs(cache.getsub(self, "headframes")) do
        insert(headframes, id)
    end
    local C = cache.get(self)
    local head_cur, headframe_cur = C.head_cur or 0, C.headframe_cur or 0
    return {
        head_cur = head_cur,
        headframe_cur = headframe_cur,
        heads = heads,
        headframes = headframes
    }
end

local function onchange_calc(self)
    local C = cache.get(self)
    local head_cur, headframe_cur = C.head_cur or 0, C.headframe_cur or 0
    local head = (headframe_cur << 32) | head_cur
    self.head = head
    roleinfo.change(self, "head", head)
end

local function onchange_head(self)
    onchange_calc(self)
    event.occur("EV_HEAD_CHG", self)
end

require("role.mods") {
    name = NM,
    load = onchange_calc,
    enter = function(self)
        client.enter(self, NM, "head_info", packall(self))
    end
}

local function head_add(self, nms, pkts, option, items)
    local C = cache.getsub(self, "heads")
    nms.head_add = NM
    for _, cfg in ipairs(items) do
        local id, cnt = cfg[2], cfg[3]
        assert(CFG_HEAD[id] and cnt > 0)
        if id ~= 0 and not C[id] then
            C[id] = true
            cache.dirty(self)
            flowlog.platlog(self, "head", {
                opt = "add",
                flag = option.flag,
                arg1 = option.arg1,
                arg2 = option.arg2,
                id = id
            }, "item", {
                action = 1,
                tp = awardtype.head,
                id = id,
                change = 1,
                last = 1
            })
            insert(pkts.head_add, {id = id})
        end
    end
    return true
end

function _M.head_del(self, id, option)
    local C = cache.getsub(self, "heads")
    if C[id] then
        C[id] = nil
        cache.dirty(self)
        flowlog.platlog(self, "head", {
            opt = "del",
            flag = option.flag,
            arg1 = option.arg1,
            arg2 = option.arg2,
            id = id
        }, "item", {
            action = -1,
            tp = awardtype.head,
            id = id,
            change = 1,
            last = 0
        })
        if C.head_cur == id then
            C.head_cur = nil
            cache.dirty(self)
            onchange_head(self)
        end
        client.enter(self, NM, "head_info", packall(self))
    end
    return true
end

local function headframe_add(self, nms, pkts, option, items)
    local C = cache.getsub(self, "headframes")
    nms.headframe_add = NM
    for _, cfg in ipairs(items) do
        local id, cnt = cfg[2], cfg[3]
        assert(CFG_HEADFRAME[id] and cnt > 0)
        if not C[id] then
            C[id] = true
            cache.dirty(self)
            flowlog.platlog(self, "headframe", {
                opt = "add",
                flag = option.flag,
                arg1 = option.arg1,
                arg2 = option.arg2,
                id = id
            }, "item", {
                action = 1,
                tp = awardtype.headframe,
                id = id,
                change = 1,
                last = 1
            })
            insert(pkts.headframe_add, {id = id})
        end
    end
    return true
end

function _M.headframe_del(self, id, option)
    local C = cache.getsub(self, "headframes")
    if C[id] then
        C[id] = nil
        cache.dirty(self)
        flowlog.platlog(self, "head", {
            opt = "del",
            flag = option.flag,
            arg1 = option.arg1,
            arg2 = option.arg2,
            id = id
        }, "item", {
            action = -1,
            tp = awardtype.headframe,
            id = id,
            change = 1,
            last = 0
        })
        if C.headframe_cur == id then
            C.headframe_cur = nil
            cache.dirty(self)
            onchange_head(self)
        end
        client.enter(self, NM, "head_info", packall(self))
    end
    return true
end

award.reg {type = awardtype.head, add = head_add}
award.reg {type = awardtype.headframe, add = headframe_add}

function _M.add_by_hero(self, tab)
    local headid = CFG_TAB[tab]
    if headid then
        award.add(self, {flag = "add_by_hero", arg1 = tab},
            {{awardtype.head, headid, 1}})
    end
end

-- id为0表示默认头像或头像框
function _H.head_change(self, msg)
    local id = msg.id
    if id ~= 0 and not cache.getsub(self, "heads")[id] then return {e = 1} end
    cache.get(self).head_cur = id
    cache.dirty(self)
    onchange_head(self)
    flowlog.role_act(self, {flag = "head_change", arg1 = id})
    return {e = 0}
end

function _H.headframe_change(self, msg)
    local id = msg.id
    if id ~= 0 and not cache.getsub(self, "headframes")[id] then
        return {e = 1}
    end
    cache.get(self).headframe_cur = id
    cache.dirty(self)
    onchange_head(self)
    flowlog.role_act(self, {flag = "headframe_change", arg1 = id})
    return {e = 0}
end

return _M
