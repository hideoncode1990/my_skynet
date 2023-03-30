local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local drop = require "role.drop"
local award = require "role.award"
local uniq = require "uniq.c"
local objtype = require "legion_trial.objtype"
local client = require "client"
local cache = require("legion_trial.cache")("box")
local schema = require "mongo.schema"
cache.schema(schema.NOBJ())
local uaward = require "util.award"
local _M = {}

local CFG
skynet.init(function()
    CFG = cfgproxy("legion_trial_box")
end)

function _M.enter(self)
    local C = cache.get(self)
    client.push(self, "legion_trial_objs", {objs = C})
    return C
end

function _M.new(self, pos, objid, groupid)
    local mainline = self.mainline
    local pool_cfg = CFG[groupid]
    local dropid
    for _, cfg in ipairs(pool_cfg) do
        if mainline >= cfg.mainline then dropid = cfg.drop end
    end
    local reward = drop.calc(dropid)
    local uuid = uniq.id()
    local obj = {
        type = objtype.box,
        uuid = uuid,
        pos = pos,
        objid = objid,
        reward = reward,
        award = uaward.pack(reward)
    }
    local C = cache.get(self)
    C[uuid] = obj
    cache.dirty(self)
    return obj
end

function _M.select(self, uuid)
    local C = cache.get(self)
    local obj = C[uuid]
    if not skynet.call(self.addr, "lua", "award_add",
        {flag = "legion_trial_box"}, obj.reward) then return false, 11 end
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
