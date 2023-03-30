local utime = require "util.time"
local skynet = require "skynet"
local service = require "skynet.service"
local platlog = require "platlog"

local flowlog
skynet.init(function()
    flowlog = service.query("flowlog")
end)

local _M = {}

function _M.role(self, coll, s)
    s.rid = self.rid
    s.rname = self.rname
    s.uid = self.uid
    s.sid = self.sid
    s.optime = utime.time()
    s.channel = self.channel
    s.dev_id = self.dev_id
    s.dev_type = self.dev_type
    s.level = self.level
    skynet.send(flowlog, "lua", "add", "insert", coll, s)
end

function _M.role_act(self, s)
    _M.role(self, "actions", s)
end

function _M.login(self, uuid, s)
    s.uuid = uuid
    s.rid = self.rid
    s.rname = self.rname
    s.uid = self.uid
    s.sid = self.sid
    s.optime = utime.time()
    s.channel = self.channel
    s.dev_id = self.dev_id
    s.dev_type = self.dev_type
    s.level = self.level
    s.ip = self.ip
    skynet.send(flowlog, "lua", "add", "insert", "login", s)
end

function _M.logout(self, uuid, ti, online_time)
    skynet.send(flowlog, "lua", "add", "update", "login", {uuid = uuid}, {
        leavetime = ti,
        online_time = online_time,
        leavelevel = self.level
    })
end

function _M.platlog(self, coll, s, plname, d)
    _M.role(self, coll, s)
    if d then for k, v in pairs(d) do s[k] = v end end
    platlog(plname, s, self)
end

function _M.logemail(email)
    skynet.send(flowlog, "lua", "add", "insert", "email", email)
end

return _M
