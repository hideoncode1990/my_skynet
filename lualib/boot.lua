local skynet = require "skynet"
local format = string.format
local env = require "env"

local array = {}

local function R(func, ...)
    if select("#", ...) == 0 then
        table.insert(array, func)
    else
        local args = {...}
        table.insert(array, function()
            func(table.unpack(args))
        end)
    end
end

local _M = setmetatable({}, {
    __call = function(_, func, ...)
        R(func, ...)
    end
})

local function bootstrap()
    skynet.error("Server start")
    while true do
        local func = table.remove(array, 1)
        if not func then break end
        func()
    end
end

function _M.main()
    local procuuid = env.procuuid
    local ok, err = xpcall(bootstrap, debug.traceback)
    if not ok then
        skynet.error(format("boot %s end failure used %d %s", procuuid,
            skynet.now(), err))
        skynet.newservice("quit")
    else
        skynet.error(format("boot %s end success used %d", procuuid,
            skynet.now()))
    end
end

function _M.open_setting()
    R(require("setting.loader").init)
end

function _M.open_base()
    R(function()
        if not env.daemon then skynet.uniqueservice "console" end
        skynet.newservice "base/console"
        skynet.uniqueservice "base/debuggerd"
        skynet.uniqueservice "base/framegraph"
    end)
    R(function()
        local sid = assert(tonumber(env.node_id))
        local node = env.node_type
        local _type
        if node == "func" then _type = 1 end
        require("skynet.service").new("uniq.c", function(...)
            require("uniq.c").init(...)
        end, sid, _type)
    end)
end

function _M.open_cluster()
    R(skynet.uniqueservice, "base/monitord")
    R(function()
        skynet.call(skynet.uniqueservice("base/clustermgr"), "lua", "open")
    end)
end

function _M.open_cfg()
    R(skynet.newservice, "base/cfgloader")
end

function _M.open_sproto()
    R(function()
        local proto = skynet.uniqueservice "protoloader"
        skynet.call(proto, "lua", "load", {"proto.c2s", "proto.s2c"})
    end)
end

return _M
