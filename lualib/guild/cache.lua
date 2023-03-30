local skynet = require "skynet"
local collection, delay = "guild", 300
local mongo = require("mongo.help.one")("DB_FUNC", collection)
local utable = require "util.table"
local getsub = utable.getsub
local sub = utable.sub

local _M = {}

local DIRTY
local dirty_cache = {}

local GID
local DATA = {}
local SAVE_PROXY = {}
local PROXY_CLASS = {}

local function save()
    DIRTY = nil
    if next(dirty_cache) then
        local ds
        ds, dirty_cache = dirty_cache, {}
        local data = {}
        for k in pairs(ds) do
            local d = SAVE_PROXY[k]
            local class = PROXY_CLASS[k]
            local encode = class and class.encode
            if encode then d = encode(d) end
            data[k] = d
        end
        mongo("safe", "update", collection, {gid = GID}, data, false, false)
    end
end

function _M.load(gid)
    DATA = mongo("findone", collection, {gid = gid}, {_id = 0})
    GID = gid
    return setmetatable(SAVE_PROXY, {
        __index = function(t, k)
            local v = sub(DATA, k)
            local class = PROXY_CLASS[k]
            local decode = class and class.decode
            if decode then v = decode(v) end
            t[k] = v
            return v
        end
    })
end

function _M.del()
    mongo("safe", "delete", collection, {gid = GID})
end

local function dirty(...)
    for _, k in pairs({...}) do dirty_cache[k] = true end
    if not DIRTY then
        DIRTY = true
        skynet.timeout(delay, function()
            if DIRTY then save() end
        end)
    end
end

_M.dirty = dirty
_M.unload = function()
    while DIRTY do save() end
end

return setmetatable(_M, {
    __call = function(_, k)
        local function get()
            return SAVE_PROXY[k]
        end
        return {
            get = get,
            getsub = function(...)
                return getsub(get(), ...)
            end,
            dirty = function()
                dirty(k)
            end,
            schema = function(_schema)
                PROXY_CLASS[k] = {
                    decode = function(d)
                        return _schema(false, d)
                    end,
                    encode = function(d)
                        return _schema(true, d)
                    end
                }
            end
        }
    end
})
