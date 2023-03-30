local _IN = require "handler.inner"
local skynet = require "skynet"
local _M = {}

local calendard
skynet.init(function()
    calendard = skynet.uniqueservice("base/calendard")
end)

local CACHE = {}
local _MT = {
    __gc = function(t)
        local cron, cb = t.cron, t.cb
        if not cron then return end
        t.cron = nil
        local cbs = CACHE[cron]
        if cbs then
            for idx, c in ipairs(cbs) do
                if cb == c then
                    table.remove(cbs, idx)
                    break
                end
            end
            if #cbs == 0 then
                CACHE[cron] = nil
                skynet.call(calendard, "inner", "cron_unsubscribe",
                    skynet.self(), cron)
            end
        end
    end
}

function _M.subscribe(cb, cron)
    local cbs = CACHE[cron]
    if cbs then
        table.insert(cbs, cb)
    else
        cbs = {cb}
        CACHE[cron] = cbs
        skynet.call(calendard, "inner", "cron_subscribe", skynet.self(), cron) -- 等待订阅完成
    end
    return setmetatable({cron, cb}, _MT)
end

function _M.unsubscribe(ret)
    _MT.__gc(ret)
end

function _IN.calendard_timeout(cron)
    local cbs = CACHE[cron]
    if cbs then for _, cb in ipairs(cbs) do skynet.fork(cb) end end
end

function _M.next_time(cron, lastti)
    return skynet.call(calendard, "inner", "next_time", cron, lastti)
end

function _M.near_time(cron, lastti)
    return skynet.call(calendard, "inner", "near_time", cron, lastti)
end

return _M
