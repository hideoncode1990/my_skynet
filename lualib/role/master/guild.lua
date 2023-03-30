local skynet = require "skynet"
local _MAS = require "handler.master"
require "role.master.time"

function _MAS.guild(self, ctx)
    local query = ctx.query
    local exp = query.exp or 0
    skynet.send(skynet.uniqueservice("guild/proxy"), "lua", "add_contribution",
        self.rid, exp)
    return {e = 0}
end

