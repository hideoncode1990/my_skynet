local uniq = require "uniq.c"
local client = require "client"
local cache = require "legion_trial.cache"("transport")
local schema = require "mongo.schema"
cache.schema(schema.NOBJ())
local objtype = require "legion_trial.objtype"
local _M = {}

function _M.enter(self)
    local C = cache.get(self)
    client.push(self, "legion_trial_objs", {objs = C})
    return C
end

function _M.new(self, pos, objid, sceneid)
    local C = cache.get(self)
    local uuid = uniq.id()
    local obj = {
        type = objtype.transport,
        uuid = uuid,
        pos = pos,
        objid = objid,
        sceneid = sceneid
    }
    C[uuid] = obj
    cache.dirty(self)
    return obj
end

function _M.transport(self, uuid)
    local C = cache.get(self)
    local obj = C[uuid]
    return obj.sceneid
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

