local vminfo = require "debug.vminfo"
local json = require "rapidjson.c"
local net = require "robot.net"
local _H = require "handler.client"

function _H.debug_vmregister(self, msg)
    local session = msg.session
    local keys, vals = vminfo(debug.getregistry(), table.unpack(msg.keys))
    local result = json.encode({keys = keys, vals = vals})
    while #result > 32657 do
        net.push(self, "debug_longstring",
            {session = session, data = result:sub(1, 32657)})
        result = result:sub(32658)
    end
    net.push(self, "debug_longstring_over", {session = session, data = result})
end
