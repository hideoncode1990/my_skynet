local skynet = require "skynet"
local service = require "service.release"

local refd
skynet.init(function()
    refd = skynet.uniqueservice("base/refd")
end)

local _M = {}

local inited
function _M.init(delay)
    inited = true
    service.release("reference.server", function()
        inited = false
        skynet.call(refd, "lua", "release_mark", skynet.self())
    end)
    setmetatable(_M, {
        __gc = function()
            skynet.send(refd, "lua", "release", skynet.self())
        end
    })
    skynet.send(refd, "lua", "init", skynet.self(), delay)
end

function _M.ref()
    assert(inited)
    return skynet.call(refd, "lua", "ref", skynet.self())
end

function _M.unref()
    if inited then return skynet.call(refd, "lua", "unref", skynet.self()) end
end

return _M
