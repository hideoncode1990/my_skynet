local variable = require "variable"

require("client.control").reg("clientcontrol", function(_, msg_name)
    local cmds = variable.clientcontrol
    if cmds[msg_name] then return {e = 0xffff} end
end)
