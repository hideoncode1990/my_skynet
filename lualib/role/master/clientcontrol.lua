local _H = require "handler.client"
local _MAS = require "handler.master"

function _MAS.client_cmdlist()
    local cmds = {}
    for nm in pairs(_H) do table.insert(cmds, nm) end
    return cmds
end
