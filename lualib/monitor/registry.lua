local skynet = require "skynet"
local _IN = require "handler.inner"

local _CBS = {}
function _IN.monitor_info()
    local d = {}
    for _, cb in pairs(_CBS) do cb(d) end
    return d
end

return function(key, cb)
    if not next(_CBS) then
        skynet.fork(function()
            skynet.send(skynet.uniqueservice("base/monitord"), "lua",
                "register", skynet.self())
        end)
    end
    _CBS[key] = cb
end
