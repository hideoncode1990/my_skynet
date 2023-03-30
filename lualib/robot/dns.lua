local function dns_service()
    local skynet = require "skynet"
    local dns = require "skynet.dns"
    skynet.dispatch("lua", function(_, _, cmd, ...)
        skynet.retpack(dns[cmd](...))
    end)
    skynet.start(function()
    end)
end

local service = require "skynet.service"
local skynet = require "skynet"

local dnsd

local _M = {}

function _M.server( --[[server, port]] )
    -- skynet.call(dnsd, "lua",  "server", server, port)
end

function _M.resolve(name, ipv6)
    return skynet.call(dnsd, "lua", "resolve", name, ipv6)
end

skynet.init(function()
    dnsd = service.new("global_dns", dns_service)
    local dns = require "skynet.dns"
    dns.server = _M.server
    dns.resolve = _M.resolve
    require("http.httpc").dns()
end)

return _M
