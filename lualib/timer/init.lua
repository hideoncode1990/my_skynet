local skynet = require "skynet"
local utime = require "util.time"
local minheap = require "minheap.c"

local heap_push, heap_pop, heap_top = minheap.add, minheap.pop, minheap.top
local mathmin = math.min
local mathmax = math.max

local skynet_timeout = skynet.timeout
local skynet_wakeup = skynet.wakeup
local skynet_wait = skynet.wait
local time_now = utime.now
local running = coroutine.running

local maxinteger<const> = math.maxinteger
local HEAP = minheap.new()
local IDCUR, ID2CB = 1, {}
local MIN_TI, MIN_ALL = maxinteger, {}

local update
local function skynet_poll(now)
    local _, min = heap_top(HEAP)
    if min then
        min = mathmin(now + 6000, min)
        if min < MIN_TI then
            MIN_TI = min
            if not MIN_ALL[min] then
                MIN_ALL[min] = true
                local diff = mathmax(0, min - now) -- diff need -0x7FFFFFFF < diff < 0x7FFFFFFF
                diff = mathmin(diff, 0x7FFFFFFF)
                skynet_timeout(diff, function()
                    MIN_ALL[min] = nil
                    now = time_now()
                    update(now)
                    if MIN_TI == min then
                        MIN_TI = maxinteger
                        skynet_poll(now)
                    end
                end)
            end
        end
    end
end

local function timeout(id, now)
    local call = ID2CB[id]
    if call then
        ID2CB[id] = nil
        call(now)
    end
end

-- update is local function
function update(now)
    while true do
        local id = heap_pop(HEAP, now)
        if not id then break end
        if ID2CB[id] then skynet.fork(timeout, id, now) end
    end
    skynet_poll(now)
end

local _M = {}

local function addexpire(expire, cb)
    local id = IDCUR
    IDCUR, ID2CB[id] = IDCUR + 1, cb
    heap_push(HEAP, id, math.floor(expire))
    skynet_poll(time_now())
    return id
end

local function add(ti, cb)
    local now = time_now()
    local expire = now + ti
    return addexpire(expire, cb)
end

_M.add = add
_M.addexpire = addexpire

function _M.del(id)
    local cb = ID2CB[id]
    ID2CB[id] = nil
    return cb
end

function _M.sleep(ti)
    local co = running()
    add(ti, function()
        skynet_wakeup(co)
    end)
    skynet_wait(co)
end

return _M
