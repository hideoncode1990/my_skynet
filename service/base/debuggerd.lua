local skynet = require "skynet"
local codecache = require "skynet.codecache"
local cluster = require "skynet.cluster"
local service = require "service"
local utime = require "util.time"

local _MAS = require "handler.master"
local _LUA = require "handler.lua"

local function adjust_address(address)
    if address:sub(1, 1) ~= ":" then
        address = assert(tonumber("0x" .. address), "Need an address") |
                      (skynet.harbor(skynet.self()) << 24)
    end
    return address
end

function _MAS.list(ctx)
    local uniq, more = tonumber(ctx.query.uniq), tonumber(ctx.query.more)
    local ret = {}
    local list
    if uniq == 1 then
        list = {}
        for name, addr in pairs(skynet.call(".service", "lua", "LIST")) do
            list[addr] = name
        end
    else
        list = skynet.call(".launcher", "lua", "LIST")
    end
    for addr, name in pairs(list) do
        if addr:sub(1, 1) == ":" then
            if more == 1 then
                local t = skynet.hpc()
                local ok, info = pcall(skynet.call, addr, "debug", "STAT")
                if ok then
                    info.addr = addr
                    info.ping = (skynet.hpc() - t) / 1000000
                    info.name = name
                    table.insert(ret, info)
                end
            else
                table.insert(ret, {name = name, addr = addr})
            end
        else
            table.insert(ret, {name = name})
        end
    end
    return {e = 0, list = ret}
end

function _MAS.mem(_)
    local list = skynet.call(".launcher", "lua", "MEM")
    return {e = 0, list = list}
end

local function master_pcall(call)
    local ok, ret = pcall(call)
    if ok then return ret end
    return {e = 1, m = ret}
end

function _MAS.detail(ctx)
    return master_pcall(function()
        local address = adjust_address(ctx.query.addr)
        local ok, err = skynet.call(address, "debug", "RUN",
            "require 'debug.vmdetail'")
        if not ok then return {e = 1, m = err} end
        local t = skynet.hpc()
        local ret = skynet.call(address, "debug", "DETAIL",
            tonumber(ctx.query.task))
        ret.ping = (skynet.hpc() - t) / 1000000
        return {e = 0, ret = ret}
    end)
end

function _MAS.detailtask(ctx)
    return master_pcall(function()
        local address = adjust_address(ctx.query.addr)
        local ok, err = skynet.call(address, "debug", "RUN",
            "require 'debug.vmdetail'")
        if not ok then return {e = 1, m = err} end
        return {
            e = 0,
            bt = skynet.call(address, "debug", "DETAIL_TASK",
                assert(ctx.query.co))
        }
    end)
end

function _MAS.kill(ctx)
    local ok, err = pcall(skynet.call, ".launcher", "lua", "KILL",
        ctx.query.addr)
    if ok then
        return {e = 0}
    else
        return {e = 1, m = err}
    end
end

function _MAS.stop(ctx)
    local ok, err = pcall(skynet.call, adjust_address(ctx.query.addr), "lua",
        "stop")
    if ok then
        return {e = 0}
    else
        return {e = 1, m = err}
    end
end

function _MAS.exit(ctx)
    local ok, err = pcall(skynet.call, adjust_address(ctx.query.addr), "debug",
        "RUN", 'require("skynet").fork(require("skynet").exit)')
    if not ok then
        return {e = 1, m = err}
    else
        return {e = 0}
    end
end

function _MAS.start(ctx)
    local ok, addr = pcall(skynet.newservice, ctx.query.val)
    if ok then
        if addr then
            return {e = 0, addr = skynet.address(addr)}
        else
            return {e = 1, m = "Exit"}
        end
    else
        return {e = 3, m = "Failed"}
    end
end

function _MAS.gc(ctx)
    if ctx.query.addr then
        local address = adjust_address(ctx.query.addr)
        skynet.send(address, "debug", "GC")
        return {e = 0}
    else
        return {e = 0, list = skynet.call(".launcher", "lua", "GC")}
    end
end

function _MAS.gcall()
    local list = skynet.call(".launcher", "lua", "LIST")
    for address in pairs(list) do pcall(skynet.call, address, "debug", "GC") end
    return {e = 0}
end

function _MAS.registry(ctx)
    local address = adjust_address(ctx.query.addr)
    local ok, err = skynet.call(address, "debug", "RUN",
        "require 'debug.registry'")
    if not ok then return {e = 1, m = err} end

    local keys, vals = skynet.call(address, "debug", "REGISTRY", ctx.body.show,
        ctx.body.val or {})
    return {e = 0, vals = vals, keys = keys}
end

function _MAS.clearcache()
    codecache.clear()
    return {e = 0}
end

function _LUA.changetime(timestamp)
    local now = utime.time_int()
    local diff = timestamp - now
    if diff > 0 then
        utime.time_elapse(diff)
        local nnow = utime.time_int()
        skynet.error("changetime", nnow, diff)
        return nnow, diff
    end
end

function _LUA.update_cluster()
    skynet.call(skynet.uniqueservice("base/debugservice"), "lua",
        "base/reloadclusters")
    return {e = 0}
end

function _LUA.update_gamestat()
    skynet.send(skynet.uniqueservice("game/tokenmgr"), "lua", "gamestat_query")
end

service.start {
    master = "/debug",
    init = function()
        cluster.register("debuggerd")
    end
}
