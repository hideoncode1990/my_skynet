local skynet = require "skynet"
local site = require "site"
local watch = require "watch"
local log = require "log"
local utable = require "util.table"
local env = require "env"
local forcecenter = tonumber(env.forcecenter)

local clusters_center
if forcecenter ~= nil then
    clusters_center = setmetatable({["center_" .. forcecenter] = true},
        {__call = print})
else
    clusters_center = require("setting.factory").proxy("clusters_center")
end

local coroutine = coroutine
local assert = assert
local table = table
local pcall = pcall
local type = type

local _M = {}

local query = {}
local cache = {}

local lastcenter
local function checkcenter()
    if lastcenter then
        if pcall(site.call, lastcenter, "ping") then return lastcenter end
    end
    local w = watch()
    for node in pairs(clusters_center) do
        local cmgr = {node = node, addr = "@center_manager"}
        local ok = w:connect(node, true)
        if ok then
            lastcenter = cmgr
            return cmgr
        end
    end
    return false, "not found center"
end

--- @return table | nil, string
local function query_info(func, nowait)
    local info = cache[func]
    if not info or type(info) == 'string' then
        local inquery = query[func]
        if inquery then
            local co = coroutine.running()
            table.insert(inquery, co)
            skynet.wait(co)
        else
            inquery = {}
            query[func] = inquery
            local ok, siteaddr
            for node in pairs(clusters_center) do
                local cmgr = {node = node, addr = "@center_manager"}
                ok, siteaddr = pcall(site.call, cmgr, "query", func, nowait)
                if ok then
                    if siteaddr then
                        skynet.fork(function()
                            watch():watch(siteaddr)
                            cache[func] = nil
                        end)
                        site.addr_tryself(siteaddr)
                    else
                        siteaddr = "not found"
                    end
                    break
                end
            end
            cache[func] = siteaddr
            for _, co in ipairs(inquery) do skynet.wakeup(co) end
            query[func] = nil
        end
    end
    info = cache[func]
    if type(info) == 'string' then
        return nil, info
    else
        return info
    end
end

function _M.waitcall(func, ...)
    local info = assert(query_info(func))
    return site.call(info, ...)
end

function _M.call(func, ...)
    local info = assert(query_info(func, true))
    return site.call(info, ...)
end

local function fork_send(func, ...)
    local info = assert(query_info(func))
    site.send(info, ...)
end

function _M.send(func, ...)
    skynet.fork(fork_send, func, ...)
end

function _M.queryaddr(func)
    return assert(query_info(func, true))
end

function _M.waitaddr(func)
    return assert(query_info(func))
end

function _M.register_service(func)
    skynet.fork(function()
        local w = watch()
        while true do
            local center = checkcenter()
            if center then
                w:start(center, function()
                    assert(site.call(center, "register", func, site.self()))
                end)
                log("watch center_manager failure redo %s(%s)", func,
                    site.self())
            else
                skynet.sleep(100)
            end
        end
    end)
end

local function _watch(func)
    local info = assert(query_info(func))
    return watch():watch(info)
end

function _M.watch(func)
    return pcall(_watch, func)
end

return _M
