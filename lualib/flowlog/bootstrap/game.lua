local skynet = require "skynet"
local service = require "skynet.service"

require("bootstrap")(function()
    local main = require "flowlog.main"
    local dbmgr = skynet.uniqueservice("db/mgr")
    local proxys = skynet.call(dbmgr, "lua", "query_list", "DB_LOG")
    service.new("flowlog", main, proxys)
end)
