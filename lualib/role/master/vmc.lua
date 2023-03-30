local skynet = require "skynet"
local client = require "client"
local bigmsg = require "debug.bigmsg"
local json = require "rapidjson.c"

local _MAS = require "handler.master"

function _MAS.vmc(self, ctx)
    local session = skynet.genid()
    client.push(self, "debug_vmregister",
        {session = session, keys = ctx.body.val or {}})

    local ok, err = bigmsg.wait(session, 500)
    if not ok then return {e = 1, m = err} end

    local res = json.decode(ok)
    res.e = 0
    return res
end
