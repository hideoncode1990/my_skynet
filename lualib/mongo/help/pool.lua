local skynet = require "skynet"
local service = require "service.release"
local remove, insert = table.remove, table.insert
return function(dbname, desc)
    local proxys
    skynet.init(function()
        local dbmgr = skynet.uniqueservice("db/mgr")
        proxys = skynet.call(dbmgr, "lua", "query_list", dbname)
    end)
    local cntall, cntfin = 0, 0
    service.release(desc or dbname .. "_proxy_pool", function()
        while cntall ~= cntfin do skynet.sleep(5) end
    end)
    local waitq = {}
    local function proxy_free(proxy)
        insert(proxys, proxy)
        local co = remove(waitq, 1)
        if co then skynet.wakeup(co) end
    end
    local function proxy_alloc()
        local proxy = remove(proxys, 1)
        if proxy then
            return proxy
        else
            local co = coroutine.running()
            insert(waitq, co)
            skynet.wait(co)
            return proxy_alloc()
        end
    end

    return function(method, ...)
        local msg = skynet.packstring(method, ...)
        cntall = cntall + 1
        local proxy = proxy_alloc()
        local ok, data, sz = pcall(skynet.rawcall, proxy, "lua", msg)
        proxy_free(proxy)
        cntfin = cntfin + 1
        if not ok then error(data) end
        return skynet.unpack(data, sz)
    end
end

