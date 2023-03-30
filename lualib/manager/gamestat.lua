local skynet = require "skynet"
local httpc = require "http.httpc"
local uurl = require "util.url"
local json = require "rapidjson.c"
local utime = require "util.time"
local gamesid = require "game.sid"
local log = require "log"
local env = require "env"

local _LUA = require "handler.lua"

-- local status_closed<const> = 0
-- local status_hidden<const> = 1
-- local status_maintaining<const> = 2
local status_flow<const> = 3
-- local status_crowded<const> = 4
-- local status_full<const> = 5

local _M = {}
local _META = {
    __index = function(t, k)
        local v = {}
        t[k] = v
        return v
    end
}
local STATUS = setmetatable({}, _META)

local function serverlist_get(url, name)
    local host, path = uurl.parse(url, name)
    local header = {}
    local code, body = httpc.get(host, path, header)
    assert(code == 200, body)
    return json.decode(body)
end

local function query()
    local setting_host = env.setting_host
    local serverlist = serverlist_get(setting_host, "gamestat.json")
    local status = setmetatable({}, _META)
    for pkg, list in pairs(serverlist) do
        for _, scfg in ipairs(list) do
            local sid, st = scfg.id, scfg.status
            if gamesid[sid] then
                status[sid][pkg] = st
                log("pkg %s %s in %s", pkg, st, sid)
            end
        end
    end
    STATUS = status
end

function _M.check(sid, uid, pkg, iswhite, isblack, black)
    local st = STATUS[sid][pkg]
    if not st then
        log("can't find pkg %s(%s) w:%s b:%s", uid, tostring(pkg), iswhite,
            isblack)
        return 5
    end
    local now = utime.time()
    if isblack and now < isblack then return 6 end
    if black and now < black then return 6 end
    if iswhite and now < iswhite then return 0 end
    if st < status_flow then return 7 end
    return 0
end

_M.init = query
_LUA.gamestat_query = query

return _M
