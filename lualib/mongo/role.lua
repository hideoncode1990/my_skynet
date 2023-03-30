local skynet = require "skynet"
local logerr = require "log.err"
local LOCK = require "skynet.queue"

local utable = require "util.table"

local SAVE, VER, SAVE_LOCK, DIRTY, INSAVE
local SAVE_PROXY = {}
local PROXY_CLASS = {}

local traceback = debug.traceback
local xpcall = xpcall
local getsub = utable.getsub
local sub = utable.sub

local _M = {}

local collection = "player"

local function load_record(self)
    return skynet.call(self.proxy, "lua", "findone", collection,
        {rid = self.rid})
end

local function save_record(self, data)
    return skynet.call(self.proxy, "lua", "update", collection,
        {rid = self.rid}, data, false, false)
end

local function load_inner(self)
    if not SAVE then
        SAVE_LOCK(function()
            if not SAVE then SAVE = load_record(self) end
        end)
    end
    return SAVE
end

local function get_data()
    local ds, ver = {}, {}
    for k, v in pairs(VER) do
        local class = PROXY_CLASS[k]
        local d = SAVE_PROXY[k]

        local encode = class and class.encode
        if encode then d = assert(encode(d)) end
        ds[k], ver[k] = d, v
    end
    return ds, ver
end

local function save(self)
    if not DIRTY or not next(VER) then return end
    local data, ver = get_data()
    local ok, err = xpcall(save_record, traceback, self, data)
    if not ok then
        logerr(err)
    else
        for k, v in pairs(ver) do if v == VER[k] then VER[k] = nil end end
    end
    assert(ok, "raised error when save")
end

local function dirty_inner(self, k)
    assert(self)
    DIRTY = true
    VER[k] = (VER[k] or 0) + 1
    if not INSAVE then
        INSAVE = true
        skynet.fork(function()
            skynet.sleep(6000)
            INSAVE = nil
            _M.save(self)
        end)
    end
end

function _M.init(self)
    VER, SAVE_LOCK = {}, LOCK()

    setmetatable(SAVE_PROXY, {
        __index = function(t, k)
            local s = load_inner(self)
            local v = s[k]
            if not v then
                v = {}
            else
                s[k] = nil
            end
            local class = PROXY_CLASS[k]
            local decode = class and class.decode
            if decode then v = decode(v) end
            t[k] = v
            return v
        end
    })

end

function _M.save(self)
    SAVE_LOCK(save, self)
end

function _M.unload(self)
    while DIRTY do
        _M.save(self)
        if not next(VER) then DIRTY = nil end
    end
    VER = nil
end

return setmetatable(_M, {
    __call = function(_, k)
        local function get()
            return SAVE_PROXY[k]
        end
        return {
            get = get,
            getsub = function(self, ...)
                return getsub(get(self), ...)
            end,
            dirty = function(self)
                dirty_inner(self, k)
            end,
            proxy = function(class)
                assert(not PROXY_CLASS[k])
                PROXY_CLASS[k] = class
            end,
            schema = function(schema)
                PROXY_CLASS[k] = {
                    decode = function(d)
                        return schema(false, d)
                    end,
                    encode = function(d)
                        return schema(true, d)
                    end
                }
            end
        }
    end
})
