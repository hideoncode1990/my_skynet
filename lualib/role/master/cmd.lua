local skynet = require "skynet"
local _MAS = require "handler.master"

function _MAS.cmd_list()
    local cmd = skynet.uniqueservice "game/cmd"
    local list = skynet.call(cmd, "lua", "cmds")
    return {e = 0, list = list}
end

function _MAS.cmd_run(self, ctx)
    local cmd = skynet.uniqueservice "game/cmd"
    local ok, code, body = skynet.call(cmd, "lua", "agent_comand", self.rid,
        ctx.body.content)
    return {e = 0, ok = ok, code = code, body = body}
end
