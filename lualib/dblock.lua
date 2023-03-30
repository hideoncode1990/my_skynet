local skynet = require "skynet"
local service = require "service.release"
local env = require "env"
local selfnode = env.node

return function(key)
    skynet.init(function()
        local ok, err = skynet.call(skynet.uniqueservice("func/dblockd"), "lua",
            "reg", key, selfnode)
        if not ok then error(setmetatable({}, {__name = "dblockd"})) end
    end)

    service.release("dblock", function()
        local ok, err = pcall(skynet.send, skynet.uniqueservice("func/dblockd"),
            "lua", "unreg", key, selfnode)
        if not ok then skynet.error(err) end
    end)
end
