local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local cache = require("legion_trial.cache")("shop")
local schema = require "mongo.schema"
cache.schema(schema.NOBJ())
local uniq = require "uniq.c"
local award = require "role.award"
local client = require "client"
local objtype = require "legion_trial.objtype"

local SHOP_CFG
skynet.init(function()
    SHOP_CFG = cfgproxy("legion_trial_shop")
end)

local _M = {}

function _M.enter(self)
    local C = cache.get(self)
    client.push(self, "legion_trial_objs", {objs = C})
    return C
end

function _M.new(self, pos, objid, num)
    local mainline = self.mainline
    local pool
    for _, v in ipairs(SHOP_CFG) do
        if mainline >= v.mainline then
            pool = v.pool
            break
        end
    end
    local total_weight = pool[0]
    local recv = {}
    while num > 0 do
        num = num - 1
        local r = math.random(total_weight)
        local w = 0
        for _, cfg in ipairs(pool) do
            if not recv[cfg.id] then
                w = w + cfg.weight
                if r <= w then
                    recv[cfg.id] = cfg
                    total_weight = total_weight - cfg.weight
                    break
                end
            end
        end
    end
    local items = {}
    for _, cfg in pairs(recv) do
        table.insert(items,
            {cost = cfg.cost, item = cfg.item, rebate = cfg.rebate})
    end
    local C = cache.get(self)
    local uuid = uniq.uuid()
    local obj = {
        type = objtype.shop,
        uuid = uuid,
        pos = pos,
        objid = objid,
        selects = items
    }
    C[uuid] = obj
    cache.dirty(self)
    return obj
end

function _M.buy(self, uuid, index)
    local C = cache.get(self)
    local obj = C[uuid]
    local o = obj.selects[index]
    if not o then return false, 1 end
    if o.selected then return false, 2 end
    local option = {flag = "legion_trial_shop_buy"}
    if not skynet.call(self.addr, "lua", "award_deladd", option, {o.cost},
        {o.item}) then return false, 4 end
    o.selected = true
    return true
end

function _M.del(self, uuid)
    local C = cache.get(self)
    C[uuid] = nil
    cache.dirty(self)
end

function _M.clean(self)
    cache.clean(self)
end

function _M.dirty(self)
    cache.dirty(self)
end
return _M
