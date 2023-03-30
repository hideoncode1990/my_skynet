local skynet = require "skynet"
local event = require "role.event"

local serverlist
skynet.init(function()
    serverlist = skynet.uniqueservice("game/serverlist")
end)

local function update(self, data)
    data.uid, data.sid = self.uid, self.sid
    skynet.send(serverlist, "lua", "update", self.rid, data)
end

event.reg("EV_HEAD_CHG", "serverlist", function(self)
    update(self, {head = self.head})
end)
