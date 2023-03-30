local skynet = require "skynet"

return setmetatable({}, {
    __index = function(t, k)
        local v = skynet.uniqueservice(k)
        rawset(t, k, v)
        return v
    end
})
