local skynet = require "skynet"
local cluster = require "skynet.cluster"

skynet.start(function()
    skynet.dispatch('lua', function(_, _, ...)
        skynet.retpack(skynet.newservice(...))
    end)
    cluster.register("debugservice")
end)
