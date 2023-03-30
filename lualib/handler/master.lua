local skynet = require "skynet"

skynet.register_protocol {
    name = "master",
    id = 100,
    pack = skynet.pack,
    unpack = skynet.unpack
}

local hs = {}

skynet.dispatch("master", function(_, _, cmd, ctx)
    local h = hs[cmd]
    if not h then
        skynet.retpack(501)
    else
        skynet.retpack(200, h(ctx))
    end
end)

return hs
