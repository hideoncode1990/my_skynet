local skynet = require "skynet"
local cluster = require "skynet.cluster"

local _M = cluster

local opend
local function wait_open()
    if opend == true then return true end
    if opend == nil then
        opend = {}
        skynet.call(skynet.uniqueservice("base/clustermgr"), "lua", "opend")
        local ops = {}
        opend, ops = true, opend
        for _, co in ipairs(ops) do
            skynet.wakeup(co)
        end
    else
        local co = coroutine.running()
        table.insert(opend, co)
        skynet.wait(co)
    end
end

function _M.opensend(...)
    skynet.fork(function(...)
        if opend ~= true then wait_open() end
        cluster.send(...)
    end, ...)
end

function _M.opencall(...)
    if opend ~= true then wait_open() end
    return cluster.call(...)
end

return _M
