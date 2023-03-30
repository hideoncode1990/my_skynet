local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local uniq = require "uniq.c"
local objtype = require "legion_trial.objtype"
local cache = require("legion_trial.cache")("buff")
local schema = require "mongo.schema"
cache.schema(schema.NOBJ())
local card = require "legion_trial.card"
local client = require "client"
local _M = {}

local CFG, GROUP_CFG
skynet.init(function()
    CFG, GROUP_CFG = cfgproxy("treasure", "treasure_group")
end)

function _M.enter(self)
    local C = cache.get(self)
    client.push(self, "legion_trial_objs", {objs = C})
    return C
end

local NUM = 3
local function rand_card(marks, pool_cfg)
    local total_w = 0
    for _, v in ipairs(pool_cfg.list) do
        local id = v[1]
        if not marks[id] then total_w = total_w + v[2] end
    end
    local cnt = 0
    local ret = {}
    while cnt < NUM do
        cnt = cnt + 1
        local r = math.random(total_w)
        local w = 0
        for _, v in ipairs(pool_cfg.list) do
            local id = v[1]
            if not marks[id] then
                w = w + v[2]
                if r <= w then
                    marks[id] = true
                    total_w = total_w - v[2]
                    table.insert(ret, {cardid = id})
                    break
                end
            end
        end
    end
    return ret
end

function _M.new(self, pos, objid, groupid)
    local my_cards = card.get(self)
    local marks = {}
    for id, cnt in pairs(my_cards) do
        local cfg = CFG[id]
        if cnt >= cfg.max then marks[id] = true end
    end
    local cards = rand_card(marks, GROUP_CFG[groupid])
    local uuid = uniq.id()
    local obj = {
        type = objtype.buff,
        uuid = uuid,
        pos = pos,
        objid = objid,
        selects = cards
    }
    local C = cache.get(self)
    C[uuid] = obj
    cache.dirty(self)
    return obj
end

function _M.select(self, uuid, index)
    local C = cache.get(self)
    local obj = C[uuid]
    local o = obj.selects[index]
    if not o then return false, 21 end
    local cardid = o.cardid
    card.addbag(self, cardid)
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

