local skynet = require "skynet"
local utable = require "util.table"
local default = require "mongo.default"
local mongo = require("mongo.help.one")(default, "activity")
local lock = require("skynet.queue")()

local getsub = utable.getsub
local insave

local collection = "activity"
local function load_record(t, name)
    local ret = mongo("findone", collection, {name = name}, {}) or {name = name}
    t[name] = ret
    return ret
end

local DIRTY_TABLE = {}
local SAVE_PROXY = setmetatable({}, {
    __index = function(t, k)
        return lock(function()
            local v = rawget(t, k)
            if v then return v end
            return load_record(t, k)
        end)
    end
})

local function saveall()
    while true do
        local name, ver = next(DIRTY_TABLE)
        if not name then break end
        mongo("update", collection, {name = name}, SAVE_PROXY[name], true, false)
        if DIRTY_TABLE[name] == ver then DIRTY_TABLE[name] = nil end
    end
end

require("service.release").release("acvivity", function()
    lock(saveall)
end)

return function(name)
    local function get()
        return SAVE_PROXY[name]
    end
    return {
        get = get,
        getsub = function(...)
            return getsub(get(), ...)
        end,
        dirty = function()
            DIRTY_TABLE[name] = (DIRTY_TABLE[name] or 0) + 1
            if not insave then
                insave = true
                skynet.fork(function()
                    skynet.sleep(600)
                    insave = nil
                    lock(saveall)
                end)
            end
        end
    }
end
