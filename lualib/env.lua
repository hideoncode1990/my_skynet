local skynet = require "skynet"

return setmetatable({}, {
    __index = function(t, k)
        local v = skynet.getenv(k)
        t[k] = v
        return v
    end
})
