local skynet = require "skynet"

local _M = {}

local dropmgr
skynet.init(function()
    dropmgr = skynet.uniqueservice("base/dropd")
end)

function _M.calc(id, count)
    return skynet.call(dropmgr, "lua", "calc", id, count)
end

function _M.render_calc(rid, count)
    return skynet.call(dropmgr, "lua", "render_calc", rid, count)
end

return _M
