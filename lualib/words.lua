local skynet = require "skynet"

local address
skynet.init(function()
    address = skynet.uniqueservice("base/words")
end)

local _M = {}

--- @param str string
--- @return boolean
function _M.dirtycheck(str)
    return skynet.call(address, "lua", "dirtycheck", str)
end

--- @param str string
--- @return string
function _M.dirtyfilter(str)
    return skynet.call(address, "lua", "dirtyfilter", str)
end

function _M.namecheck(str)
    return skynet.call(address, "lua", "namecheck", str)
end

return _M
