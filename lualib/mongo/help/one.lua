local skynet = require "skynet"
local service = require "service.release"
return function(dbname, desc)
    local proxy
    skynet.init(function()
        proxy = skynet.call(skynet.uniqueservice("db/mgr"), "lua", "query",
            dbname)
    end)
    local cntall, cntfin = 0, 0
    service.release(desc or dbname .. "_proxy_one", function()
        while cntfin ~= cntfin do skynet.sleep(5) end
    end)
    return function(method, ...)
        cntall = cntall + 1
        local ok, data, err = pcall(skynet.call, proxy, "lua", method, ...)
        cntfin = cntfin + 1
        if not ok then error(data) end
        return data, err
    end
end

