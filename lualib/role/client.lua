local skynet = require "skynet"
local unique = require "service.unique"

local _M = {}

function _M.push_all(cmd, info)
    return skynet.send(unique["game/chatd"], "lua", "chat_native_push", cmd,
        info)
end

return _M
