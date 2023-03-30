local skynet = require "skynet"
local collection = "emails"
local utime = require "util.time"

local _M = {}
function _M.read(proxy, id, ti)
    return skynet.call(proxy, "lua", "update", collection,
                       {id = assert(tonumber(id))},
                       {readtime = ti or utime.time()}, false, false)
end

function _M.delete(proxy, id)
    return skynet.call(proxy, "lua", "delete", collection,
                       {id = assert(tonumber(id))}, true)
end

function _M.findall(proxy, query, selector)
    return skynet.call(proxy, "lua", "findall", collection, query, selector)
end

function _M.findone(proxy, query, selector)
    return skynet.call(proxy, "lua", "findone", collection, query, selector)
end

function _M.delete_some(proxy, query)
    return skynet.send(proxy, "lua", "safe", "delete", collection, query, false)
end

return _M
