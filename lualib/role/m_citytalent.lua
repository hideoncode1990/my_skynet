local skynet = require "skynet"
local client = require "client"
local cfgproxy = require "cfg.proxy"
local cache = require("mongo.role")("citytalent")
local flowlog = require "flowlog"
local award = require "role.award"
local fnopen = require "role.fnopen"
local hero = require "hero"
local passive = require "role.passive"
local attrs = require "hero.attrs"
local addition = require "role.addition"
local uattrs = require "util.attrs"
local schema = require "mongo.schema"
local utable = require "util.table"
local task = require "task"

cache.schema(schema.NOBJ())

local _H = require "handler.client"

local CFG
skynet.init(function()
    CFG = cfgproxy "citytalent"
end)

require("role.mods") {
    name = "citytalent",
    enter = function(self)
        local C = cache.get(self)
        client.push(self, "citytalent_info", {list = C})
    end
}

local function calc_attrs(self, duty)
    local C = cache.get(self)
    local ret = {}
    for id, level in pairs(C) do
        local cfg = CFG[id][level]
        local cattrs = cfg.attrs
        if cattrs then
            local cduty = cfg.duty
            if cduty then
                if cduty == duty then
                    uattrs.append_array(ret, cattrs)
                end
            else
                uattrs.append_array(ret, cattrs)
            end
        end
    end
    return ret
end

local attrs_cache = setmetatable({}, {__mode = "kv"})
local function ondirty(self, duty)
    attrs_cache = setmetatable({}, {__mode = "kv"})
    if duty then
        hero.foreach(self, function(obj, uuid)
            local cfg = hero.query_cfg_byid(obj.id)
            if cfg.duty == duty then
                attrs.dirty(self, "citytalent", uuid)
            end
        end)
    else
        hero.foreach(self, function(_, uuid)
            attrs.dirty(self, "citytalent", uuid)
        end)
    end
    addition.dirty(self)
    passive.dirty(self, "citytalent")
end

attrs.reg("citytalent", function(self, uuid)
    local cfg = hero.query_cfg(self, uuid)
    local duty = cfg.duty
    local c = attrs_cache[duty]
    if not c then
        c = calc_attrs(self, duty)
        attrs_cache[duty] = c
    end
    return c
end)

addition.reg("citytalent", function(self, key, cb)
    for id, level in pairs(cache.get(self)) do
        local cfg = CFG[id][level]
        local v = cfg[key]
        if v then cb(v) end
    end
end)

passive.reg("citytalent", function(self)
    local C = cache.get(self)
    local ret = {}
    for id, level in pairs(C) do
        local cfg = CFG[id][level]
        if cfg.effect then utable.mixture(ret, cfg.effect) end
    end
    return ret
end)

function _H.citytalent_levelup(self, msg)
    local id, tlevel = msg.id, msg.level + 1
    local cfgs = CFG[id]
    local type = cfgs.type
    if not fnopen.check_open(self, "citytalent" .. type) then return {e = 1} end
    if cfgs.mainline > self.mainline then return {e = 2} end

    local C = cache.get(self)
    local level = C[id] or 0
    if level + 1 ~= tlevel then return {e = 3} end
    local cfg = cfgs[level]
    if not cfg then return {e = 2} end

    local condition = cfg.condition
    if condition then
        local cid, clevel = condition[1], condition[2]
        if (C[cid] or 0) < clevel then return {e = 4} end
    end

    local cost = cfg.cost
    local option = {flag = "citytalent_levelup", arg1 = id, arg2 = tlevel}
    local ok, err = award.del(self, option, {cost})
    if not ok then return {e = err} end

    C[id] = tlevel
    cache.dirty(self)

    task.trigger(self, "citytalent")
    flowlog.role_act(self, option)
    ondirty(self)
    return {e = 0}
end

function _H.citytalent_reset(self, msg)
    local id = msg.id
    local cfgs = CFG[id]
    local C = cache.get(self)
    local level = C[id] or 0
    if level == 0 then return {e = 1} end

    local cfg = cfgs[level]
    local cost = cfg.resetcost
    local add = cfg.returns

    local option = {flag = "citytalent_reset", arg1 = id, arg2 = level}
    local ok, err = award.deladd(self, option, {cost}, {add})
    if not ok then return {e = err} end

    C[id] = nil
    cache.dirty(self)

    flowlog.role_act(self, option)
    ondirty(self)
    return {e = 0}
end
