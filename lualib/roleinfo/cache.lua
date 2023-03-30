local skynet = require "skynet"
local logerr = require "log.err"

local insert = table.insert
local remove = table.remove

local _M = {}

local CACHE, INQUEUE = {}, {}
local QUEUE = require "circqueue"()

local collection, delay = "roleinfo", 3000

local proxys, proxys_count
skynet.init(function()
    proxys = skynet.call(skynet.uniqueservice("db/mgr"), "lua", "query_list",
        "DB_GAME")
    proxys_count = #proxys
    assert(#proxys > 0)
end)

local idx = 1
local function alloc_proxy()
    local proxy = proxys[idx]
    idx = idx + 1
    if not proxy then
        idx = 1
        return alloc_proxy()
    else
        return proxy
    end
end

local function load(rid, proxy)
    return skynet.call(proxy, 'lua', 'safe', 'findone', collection, {rid = rid})
end

local function save(rid, proxy, data)
    local ok, err = skynet.call(proxy, 'lua', 'safe', 'update', collection,
        {rid = rid}, data, true, false)
    if not ok then logerr(err) end
    return ok, err
end

local function cache_new(rid)
    local cache = CACHE[rid]
    if cache then return cache end

    cache = {proxy = alloc_proxy(), waitting = nil, data = nil}
    CACHE[rid] = cache
    return cache
end

local function cache_wait(rid)
    local cache = CACHE[rid]
    if not cache then cache = cache_new(rid) end

    if cache.data then
        return cache
    else
        local waitting = cache.waitting
        if waitting then
            local co = coroutine.running()
            table.insert(waitting, co)
            skynet.wait(co)

            if cache.data then
                return cache
            else
                return nil, cache.error
            end
        else
            waitting = {}
            cache.waitting = waitting
            local data, err = load(rid, cache.proxy)
            for _, co in ipairs(waitting) do skynet.wakeup(co) end
            cache.waitting = nil

            if data == nil and not err then
                err = "not_exist"
            elseif data then
                data._id = nil
            end

            if data then
                cache.data = data
            else
                cache.error = err
                cache = nil
                CACHE[rid] = nil
            end
            return cache, err
        end
    end
end

local function cache_save(rid)
    INQUEUE[rid] = nil
    local cache = CACHE[rid] and cache_wait(rid)
    if cache then save(rid, cache.proxy, cache.data) end
end

local function cache_queue_save()
    while true do
        local rid = QUEUE.top()
        if not rid then break end
        local ti = INQUEUE[rid]
        if ti then
            local now = skynet.now()
            local expire = ti + delay
            if expire <= now then
                QUEUE.pop()
                cache_save(rid)
            else
                skynet.sleep(expire - now + math.random(1, 500)) -- 随即延迟0到5s
            end
        else
            QUEUE.pop()
        end
    end
end

local function save_all()
    while true do
        local rid = QUEUE.pop()
        if not rid then return end

        local ti = INQUEUE[rid]
        if ti then
            INQUEUE[rid] = nil
            cache_save(rid)
        end
    end
end

local thread_num = 0
local function cache_thread_execute()
    if thread_num < proxys_count then
        thread_num = thread_num + 1
        local ok, err = pcall(cache_queue_save)
        if not ok then logerr(err) end
        thread_num = thread_num - 1
    end
end

function _M.get(rid)
    local cache, err = cache_wait(rid)
    return cache and cache.data, err
end

local function dirty(rid)
    if not INQUEUE[rid] then
        INQUEUE[rid] = skynet.now()
        QUEUE.push(rid)
        if thread_num < proxys_count then
            skynet.fork(cache_thread_execute)
        end
    end
end

function _M.set(rid, data)
    assert(not CACHE[rid])
    local cache = cache_new(rid)
    cache.data = data
    dirty(rid)
    return data
end

function _M.dirty(rid)
    dirty(rid)
end

function _M.delete(rid)
    if not CACHE[rid] then return end

    cache_wait(rid)
    while INQUEUE[rid] do cache_save(rid) end
    CACHE[rid] = nil
end

function _M.save_all()
    save_all()
end

return _M
