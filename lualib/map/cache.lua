local skynet = require "skynet"
local utable = require "util.table"
local logerr = require "log.err"

local traceback = debug.traceback
local getsub = utable.getsub
local sub = utable.sub
local xpcall = xpcall

local DATAMETHOD

local VER = {}
local SAVE, DIRTY
local SAVE_LOCK = require("skynet.queue")()
local PROXYS_CLASS = {}
local SAVE_PROXY = {}

local function get_save()
    if not SAVE then
        SAVE = SAVE_LOCK(function()
            return DATAMETHOD.load() or {}
        end)
    end
    return SAVE
end

setmetatable(SAVE_PROXY, {
    __index = function(t, k)
        local save = get_save()
        local v = sub(save, k)
        local class = PROXYS_CLASS[k]
        local decode = class and class.decode
        if decode then v = decode(v) end
        t[k] = v
        return v
    end,
    __call = function(t)
        for k in pairs(t) do t[k] = nil end

    end
})

local function save_change()
    local ds, ver = {}, {}
    for k, v in pairs(VER) do
        local class = PROXYS_CLASS[k]
        local d = SAVE_PROXY[k]
        if class then
            local encode = class.encode
            if encode then d = encode(d) end
            SAVE[k] = d
        end

        ds[k], ver[k] = d, v
    end
    return ds, ver
end

local function save_inner()
    if not DIRTY or not next(VER) then return end
    local data, ver = save_change()
    local ok, err = xpcall(DATAMETHOD.save, traceback, data, SAVE)
    if not ok then
        logerr(err)
    else
        for k, v in pairs(ver) do if v == VER[k] then VER[k] = nil end end
    end
    assert(ok, "raised error when save")
end

local function save()
    SAVE_LOCK(save_inner)
end

local function delete_inner()
    local ok, err = xpcall(DATAMETHOD.delete, traceback)
    if not ok then logerr(err) end
end

local insave
local function dirty_inner(k)
    DIRTY = true
    VER[k] = (VER[k] or 0) + 1

    if not insave then
        insave = true
        skynet.fork(function()
            skynet.sleep(1000)
            local ok, err = pcall(save)
            insave = nil
            if not ok then logerr(err) end
            return true
        end)
    end
end

local _M = {}
function _M.init(method)
    DATAMETHOD = method
end

function _M.unload()
    while DIRTY do
        save()
        if not next(VER) then DIRTY = nil end
    end
    SAVE = nil
end

function _M.delete()
    SAVE_LOCK(delete_inner)
end

_M.get = get_save

_M.inner_delete = function()
    SAVE = nil
    SAVE_PROXY()
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
                dirty_inner(k)
            end,
            proxy = function(class)
                assert(not PROXYS_CLASS[k])
                PROXYS_CLASS[k] = class
            end,
            schema = function(schema)
                PROXYS_CLASS[k] = {
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
