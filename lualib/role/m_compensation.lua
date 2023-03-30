local skynet = require "skynet"
local client = require "client"
local _H = require "handler.client"
local cache = require "mongo.role"("compensation")
local award = require "role.award"
local utable = require "util.table"
local _LUA = require "handler.lua"
local utime = require "util.time"
local NM<const> = "compensation"

local compensationd
skynet.init(function()
    compensationd = skynet.uniqueservice("game/compensationd")
end)

require "role.mods" {
    name = NM,
    enter = function(self)
        skynet.send(compensationd, "lua", "enter", skynet.self())
    end
}

local function check_list(cfg, ids)
    local ret = {}
    local now = utime.time()
    for id, v in pairs(cfg) do
        if not ids[id] and v.start <= now and now < v.stop then
            table.insert(ret, v)
        end
        ids[v.id] = nil
    end
    return ret, ids
end

function _LUA.compensation_push(self, cfg)
    local C = cache.get(self)
    local list, dels = check_list(cfg, utable.copy(C))
    client.push(self, "compensation_list", {list = list})
    if next(dels) then
        for id in pairs(dels) do C[id] = nil end
        cache.dirty(self)
    end
end

function _H.compensation_get_reward(self, msg)
    local id = msg.id
    local C = cache.get(self)
    if C[id] then return {e = 1} end
    local cfg = skynet.call(compensationd, "lua", "query")
    if not cfg then return {e = 2} end
    local v = cfg[id]
    if not v then return {e = 3} end
    local now = utime.time()
    if now < v.start or now >= v.stop then return {e = 4} end
    local ok, err = award.add(self, {flag = "compensation_reward", arg1 = id},
        v.rw)
    if not ok then return {e = err} end
    C[id] = now
    cache.dirty(self)
    return {e = 0}
end
