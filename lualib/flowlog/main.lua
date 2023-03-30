return function(freeproxy)
    local insert, remove = table.insert, table.remove

    local skynet = require "skynet"
    local service = require "service"
    local circqueue = require "circqueue"
    local _LUA = require "handler.lua"

    local freeproxycnt = #freeproxy
    assert(freeproxycnt > 0)

    local queue = circqueue()
    local finish = 0
    local function run(proxy, data)
        if not data then data = queue.pop() end
        while data do
            skynet.call(proxy, "lua", "safe", table.unpack(data))
            finish = finish + 1
            data = queue.pop()
        end
        insert(freeproxy, proxy)
    end

    require("monitor.registry")("info", function(D)
        D.flowlog_finish_total = {"counter", finish}
        D.flowlog_queue_size = {"gauge", (queue.size())}
    end)

    function _LUA.add(...)
        local proxy = remove(freeproxy)
        if proxy then
            skynet.fork(run, proxy, {...})
        else
            queue.push {...}
        end
    end

    service.start {
        regquit = true,
        release = function()
            while freeproxycnt ~= #freeproxy do skynet.sleep(10) end
        end
    }
end
