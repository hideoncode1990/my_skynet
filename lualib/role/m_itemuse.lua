local skynet = require "skynet"
local json = require "rapidjson.c"
local flowlog = require "flowlog"
local bag = require "role.m_bag"
local cfgproxy = require "cfg.proxy"
local awardtype = require "role.award.type"
local uaward = require "util.award"
local award = require "role.award"
local utime = require "util.time"
local _H = require "handler.client"
local cache = require("mongo.role")("itemuse")
local LOCK = require("skynet.queue")()

local schema = require "mongo.schema"
cache.schema(schema.OBJ({update = schema.ORI(), bought = schema.NOBJ()}))

local use = {}
for _, i in ipairs {1, 2, 3, 4, 5, 6} do
    use[i] = require(string.format("role.itemuse.%s", i))
end

local CFG
skynet.init(function()
    CFG = cfgproxy("item")
end)

local function item_use(self, msg)
    local id, count, args = msg.id, msg.count, msg.args
    assert(count > 0)
    if count > 1000 then return {e = 4} end

    local cfg = assert(bag.query_cfg(self, id))
    local usetype = cfg.usetype
    if not usetype then return {e = 3} end

    local jargs = args and json.decode(args)
    local ret = use[usetype](self, id, count, cfg, jargs)
    if ret.e ~= 0 then return ret end

    local _args = ret.args
    if _args then ret.m = json.encode(_args) end

    local items = ret.items
    if items then ret.items = uaward.pack(items) end
    flowlog.role(self, "itemuse", {usetype = usetype, id = id, count = count})
    return ret
end

function _H.item_use(self, msg)
    return LOCK(item_use, self, msg)
end

function _H.item_quickbuy(self, msg)
    local id, count = msg.id, msg.count
    local cfg = CFG[id]
    local cost = cfg.quickbuy
    if not cost then return {e = 1} end

    local amount_limit, sum, C, now = cfg.amount_limit, nil, nil, nil
    if amount_limit then
        C = cache.get(self)
        now = utime.time_int()
        if not utime.same_day(C.update or 0, now) then
            C.bought = {}
            C.update = now
            cache.dirty(self)
        end
        sum = (C.bought[id] or 0) + count
        if sum > amount_limit then return {e = 2} end
    end

    local rewards = {{awardtype.items, id, count}}

    local costs = uaward().append_one(cost).multi(count).result
    local option = {flag = "item_quickbuy", arg1 = id, arg2 = count}
    local ok, err = award.deladd(self, option, costs, rewards)
    if not ok then return {e = err} end

    if amount_limit then
        C.bought[id] = sum
        cache.dirty(self)
    end
    flowlog.role_act(self, option)
    return {e = 0}
end
