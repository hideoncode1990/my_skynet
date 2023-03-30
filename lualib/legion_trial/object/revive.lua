local uniq = require "uniq.c"
local cache = require "legion_trial.cache"("revive")
local schema = require "mongo.schema"
cache.schema(schema.NOBJ())
local battle_hero = require "legion_trial.battle_hero"
local objtype = require "legion_trial.objtype"
local client = require "client"
local _M = {}

function _M.enter(self)
    local C = cache.get(self)
    client.push(self, "legion_trial_objs", {objs = C})
    return C
end

function _M.new(self, pos, objid, coe)
    local C = cache.get(self)
    local uuid = uniq.id()
    local obj = {
        type = objtype.revive,
        uuid = uuid,
        pos = pos,
        objid = objid,
        coe = coe
    }
    C[uuid] = obj
    cache.dirty(self)
    return obj
end

function _M.select(self, uuid)
    local C = cache.get(self)
    local obj = C[uuid]
    battle_hero.revive(self, obj.coe, 1)
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
