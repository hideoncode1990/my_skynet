local skynet = require "skynet"
local _MAS = require "handler.master"

function _MAS.pay(self, ctx)
    local mainid = ctx.query.mainid

    local testpay = skynet.uniqueservice("test/pay")
    local ok, err = skynet.call(testpay, "lua", "pay", self.rid, mainid)
    return {e = ok and 0 or 1, m = err}
end
