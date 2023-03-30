local skynet = require "skynet"
local _MAS = require "handler.master"
function _MAS.map_buff(self, ctx)
    local id, cnt = ctx.query.id, ctx.query.cnt
    if not self.map_addr then return {e = 1} end
    local ok, err = skynet.call(self.map_addr, "lua", "map_buff_gm", self.rid,
        id, cnt)
    if not ok then return {e = err} end
end
