local skynet = require "skynet"
local utime = require "util.time"
local roleid = require "roleid"
local gamesid = require "game.sid"
local LOCK = require "skynet.queue"()
local mongo = require "mongo.help.one"("DB_GAME", "rolecreate")
local variable = require "variable"
local rolehelp = require "mongo.rolehelp"

local _M = {}

local CACHE = {}
local collection<const> = "player"
local role_max<const> = 0xFFFF

local counters = {}
skynet.init(function()
    for sid in pairs(gamesid) do
        local ret = mongo("findall", "player", {sid = sid}, {rid = 1, _id = 0},
            nil, 1, {rid = -1})
        local val = 0
        if next(ret) then val = roleid.getval(ret[1].rid) end
        counters[sid] = val
    end
end)

function _M.select(proxy, uid, sid)
    local role = rolehelp.select(proxy, uid, sid)
    if role then CACHE[uid] = true end
    return role
end

local function create(proxy, args)
    local _uid, _sid = args.uid, args.sid
    local val = counters[_sid]
    if val >= variable.role_max then return 6 end
    if val >= role_max then return 6 end
    val = val + 1
    local rid = roleid.genrid(_sid, val)
    local rname = args.rname
    if not skynet.call(proxy, "lua", "safe", "insert", collection, {
        rid = rid,
        rname = rname,
        sid = _sid,
        uid = _uid,
        created = utime.time_int()
    }) then return 3 end
    counters[_sid] = val
    return 0, rid, rname
end

function _M.create(proxy, args)
    return LOCK(create, proxy, args)
end

function _M.check(uid, sid)
    return CACHE[uid] or counters[sid] < variable.role_max
end

return _M
