local skynet = require "skynet"
local cache = require "map.cache"
local env = require "map.env"
local release = require "service.release"
local mods = require "map.mods"

local proxy
skynet.init(function()
    local dbmgr = skynet.uniqueservice("db/mgr")
    proxy = skynet.call(dbmgr, "lua", "query", "DB_GAME")
end)

local COLLECTION, OWNER

local _M = {}
local METHOD = {}
function METHOD.load()
    return skynet.call(proxy, "lua", "findone", COLLECTION, {owner = OWNER}) or
               {}
end

function METHOD.save(data)
    return skynet.call(proxy, "lua", "update", COLLECTION, {owner = OWNER},
        data, true, false)
end

function METHOD.delete()
    cache.inner_delete()
    return
        skynet.call(proxy, "lua", "delete", COLLECTION, {owner = OWNER}, true)
end

function _M.load(ctx)
    OWNER, COLLECTION = ctx.owner, ctx.collection
    cache.init(METHOD)
    local mapid, mainline, version, average_st, new = ctx.mapid, ctx.mainline,
        ctx.version, ctx.average_st, ctx.new
    local C
    if not new then
        C = cache("base").get()
        if C.mapid ~= mapid or C.version ~= version then new = true end
    end
    if new then
        cache.delete()
        C = cache("base").get()
        C.mapid, C.mainline, C.version, C.average_st = mapid, mainline, version,
            average_st
        cache("base").dirty()
        mods.new(ctx)
    end
    env.mainline = C.mainline
    env.average_st = C.average_st

    mods.load(ctx)
    mods.loaded(ctx)
end

release.release("map.data", function()
    cache.unload()
end)

return _M
