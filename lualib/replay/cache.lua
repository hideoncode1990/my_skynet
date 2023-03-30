local skynet = require "skynet"
local site = require "site"
local center = require "site.center"
local utime = require "util.time"
local cfgproxy = require "cfg.proxy"
local BASIC

skynet.init(function()
    BASIC = cfgproxy("basic")
end)

return function(dbname, collection)
    local _M = {}
    local CACHE = {}
    local ADD_CACHE = {}
    local mongo = require("mongo.help.pool")(dbname, collection)

    local function cache_get(uuid)
        local cache = CACHE[uuid]
        if not cache then
            cache = {data = nil, waiting = nil}
            CACHE[uuid] = cache
        end
        return cache
    end

    local function query(uuid, get, ...)
        local cache = cache_get(uuid)
        if not cache.data then
            local waiting = cache.waiting
            if waiting then
                local co = coroutine.running()
                table.insert(waiting, co)
                skynet.wait(co)
            else
                waiting = {}
                cache.waiting = waiting
                cache.data, cache.err = get(uuid, ...)
                for _, co in ipairs(waiting) do skynet.wakeup(co) end
                cache.waiting = nil
            end
        end
        return cache.data, cache.err
    end

    local function get_native(uuid)
        if ADD_CACHE[uuid] then return ADD_CACHE[uuid] end
        local data, err = mongo("findone", collection, {uuid = uuid}, {_id = 0})
        if not data then err = "not_exist" end
        if data and data.ver ~= BASIC.battle_ver then
            data, err = nil, "ver change"
            _M.del(uuid)
        end
        return data or {}, err
    end

    local function get_remote(uuid, node)
        local data, err = site.call({node = node, addr = "@replay"}, "query",
            "native", uuid)
        return data, err
    end

    local function get_center(uuid, name)
        local ok, siteaddr = pcall(center.queryaddr, name)
        if ok then return site.call(siteaddr, "query", "center", uuid) end
        return nil, "center busy"
    end
    function _M.native(uuid)
        local data, err = query(uuid, get_native)
        return data, err
    end

    function _M.remote(uuid, node)
        local data, err = query(uuid, get_remote, node)
        return data, err
    end

    function _M.center(uuid, name)
        local data, err = query(uuid, get_center, name)
        return data, err
    end

    function _M.add(data)
        local uuid = data.uuid
        if CACHE[uuid] then CACHE[uuid] = nil end -- 之前请求不到数据会缓存一个空表
        ADD_CACHE[uuid] = data
        mongo("insert", collection, data)
        ADD_CACHE[uuid] = nil
    end

    function _M.del(uuid)
        mongo("delete", collection, {uuid = uuid})
        if CACHE[uuid] then CACHE[uuid] = nil end
    end

    function _M.remove(uuid)
        if CACHE[uuid] then CACHE[uuid] = nil end
    end

    local function check_cache_expired(expire_time)
        local ti = utime.time() - expire_time
        for uuid, data in pairs(CACHE) do
            if data.ti and data.ti <= ti then CACHE[uuid] = nil end
        end
    end

    function _M.check_and_del_expire(expire_time)
        local ti = utime.time() - expire_time
        local r = mongo("delete", collection, {ti = {["$lte"] = ti}})
        if r and r.n > 0 then check_cache_expired(expire_time) end
    end

    return _M
end
