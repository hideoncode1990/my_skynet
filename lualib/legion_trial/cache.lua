local skynet = require "skynet"
local collection, delay = "legion_trial", 300
local mongo = require("mongo.help.one")("DB_GAME", collection)
local utable = require "util.table"
local getsub = utable.getsub
local sub = utable.sub

local _M = {}

local PROXY_CLASS = {}

local function save(self)
    self.dirty = nil
    local dirty_cache = self.dirty_cache
    if next(dirty_cache) then
        self.dirty_cache = {}
        local SAVE_PROXY = self.SAVE_PROXY
        local data = {}
        for k in pairs(dirty_cache) do
            local d = SAVE_PROXY[k]
            local class = PROXY_CLASS[k]
            local encode = class and class.encode
            if encode then d = encode(d) end
            data[k] = d
        end
        mongo("safe", "update", collection, {rid = self.rid}, data, true, false)
    end
end

local function load(self)
    local data = mongo("findone", collection, {rid = self.rid}, {_id = 0}) or {}
    local SAVE_PROXY = {}
    self.SAVE_PROXY = SAVE_PROXY
    self.dirty_cache = {}
    return setmetatable(SAVE_PROXY, {
        __index = function(t, k)
            local v = sub(data, k)
            data[k] = nil
            local class = PROXY_CLASS[k]
            local decode = class and class.decode
            if decode then v = decode(v) end
            t[k] = v
            return v
        end
    })
end

local function dirty(self, k)
    self.dirty_cache[k] = true
    if not self.dirty then
        self.dirty = true
        skynet.timeout(delay, function()
            if self.dirty then save(self) end
        end)
    end
end

_M.unload = function(self)
    while self.dirty do save(self) end
end

return setmetatable(_M, {
    __call = function(_, k)
        local function get(self)
            local SAVE_PROXY = self.SAVE_PROXY
            if not SAVE_PROXY then SAVE_PROXY = load(self) end
            return SAVE_PROXY[k]
        end
        return {
            get = get,
            getsub = function(self, ...)
                return getsub(get(self), ...)
            end,
            dirty = function(self)
                dirty(self, k)
            end,
            clean = function(self)
                local d = get(self)
                if next(d) then
                    local SAVE_PROXY = self.SAVE_PROXY
                    SAVE_PROXY[k] = {}
                    dirty(self, k)
                end
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
