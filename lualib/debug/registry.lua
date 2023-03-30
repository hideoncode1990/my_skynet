local skynet = require "skynet"
local skynetdebug = require "skynet.debug"
local vminfo = require "debug.vminfo"

local interface = {
    registry = debug.getregistry,
    service = function()
        local service = package.loaded["service"]
        if service then
            return service.info()
        end
    end
}

skynetdebug.reg_debugcmd("REGISTRY", function(show, keys)
    skynet.retpack(vminfo(interface[show](), table.unpack(keys)))
end)
