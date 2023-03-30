local skynet = require "skynet"
local minheap = require "minheap.c"
local service = require "service"
local utime = require "util.time"
local expression = require "calendar.expression"
local logerr = require "log.err"
local heap_add = minheap.add
local heap_pop = minheap.pop

local _IN = require "handler.inner"

local HEAP = minheap.new()
local IDCUR = 1
local IDTAB = {}

local function timeout(id, now)
    local obj = IDTAB[id]
    if not obj then return end

    local cnt = 0
    local cron_str = obj.cron_str
    for addr in pairs(obj.list) do
        cnt = cnt + 1
        skynet.send(addr, "inner", "calendard_timeout", cron_str)
    end
    if cnt == 0 then
        IDTAB[cron_str], IDTAB[id] = nil, nil
    else
        local nexti = expression.next_time(obj.cron, now)
        if nexti then
            obj.next_ti = nexti
            heap_add(HEAP, id, nexti)
        else
            IDTAB[cron_str], IDTAB[id] = nil, nil
        end
    end
end

local function update()
    local traceback = debug.traceback
    while true do
        local now = utime.time_int()
        while true do
            local id = heap_pop(HEAP, now)
            if not id then break end
            local ok, err = xpcall(timeout, traceback, id, now)
            if not ok then logerr(err) end
        end
        skynet.sleep(100)
    end
end

local cron_cache = setmetatable({}, {__mode = "v"})
local function calc_next_time(cron_str, ti)
    local cron = cron_cache[cron_str]
    if not cron then
        cron = expression.expression(cron_str)
        cron_cache[cron_str] = cron
    end
    local next_ti = expression.next_time(cron, ti or utime.time_int())
    return next_ti, cron
end

local function subscribe(addr, cron_str)
    local obj = IDTAB[cron_str]
    if obj then
        obj.list[addr] = true
        return
    end

    local next_ti, cron = calc_next_time(cron_str)
    if not next_ti then return end

    local id = IDCUR + 1
    IDCUR = id

    obj = {
        cron_str = cron_str,
        cron = cron,
        id = id,
        list = {[addr] = true},
        next_ti = next_ti
    }
    IDTAB[cron_str], IDTAB[id] = obj, obj
    heap_add(HEAP, id, next_ti)
end

function _IN.cron_subscribe(addr, cron_str)
    subscribe(addr, cron_str)
end

function _IN.cron_unsubscribe(addr, cron_str)
    local obj = IDTAB[cron_str]
    if not obj then return end
    obj.list[addr] = nil
end

function _IN.next_time(cron_str, ti)
    return (calc_next_time(cron_str, ti))
end

function _IN.near_time(cron_str, ti)
    local now = utime.time_int()
    local next_ti = calc_next_time(cron_str, ti)
    if not next_ti then return end
    if next_ti > now then
        return ti
    else
        next_ti = calc_next_time(cron_str, now)
        if not next_ti then return end
        return now
    end
end

service.start {
    init = function()
        skynet.fork(update)
    end
}
