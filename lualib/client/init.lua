local skynet = require "skynet"
local log = require "log"
local socketdriver = require "skynet.socketdriver"

local driversend = socketdriver.send


local pairs = pairs
local pack = string.pack

local string = string

local client = {}
local sender

local thread = {}
local retmsg = {}
local reterr = {}

function client.response(session, result)
    local co = thread[session]
    if not co then
        log("Invalid session " .. session)
    else
        retmsg[session] = result
        thread[session] = nil
        reterr[session] = nil
        skynet.wakeup(co)
    end
end

function client.close(self, why)
    skynet.call(self.gate, "lua", "kick", self.fd, why or "close")
end

function client.push(self, t, data)
    local msg = pack(">s2", sender(t, data))
    if self.fd then driversend(self.fd, msg) end
    return #msg
end

function client.pushfd(fd, t, data)
    if not fd then return end
    local m = sender(t, data)
    local msg = pack(">s2", m)
    driversend(fd, msg)
end

function client.pushfds(fds, t, data)
    local msg = pack(">s2", sender(t, data))
    for _, fd in pairs(fds) do driversend(fd, msg) end
end

function client.pushobjs(objs, t, data)
    local msg = pack(">s2", sender(t, data))
    local cnt = 0
    for _, obj in pairs(objs) do
        if obj.fd then driversend(obj.fd, msg) end
        cnt = cnt + 1
    end
    local sz = #msg
    return sz * cnt, cnt
end

function client.request(self, ti, t, data)
    local session = skynet.genid()
    local msg = string.pack(">s2", sender(t, data, session))
    assert(driversend(self.fd, msg))
    local co = coroutine.running()
    thread[session] = co
    skynet.timeout(ti, function()
        local o = thread[session]
        if not o then return end
        retmsg[session] = string.format("timeout %s %s", tostring(self.fd),
            tostring(t))
        reterr[session] = true
        thread[session] = nil
        skynet.wakeup(o)
    end)
    skynet.wait()
    local err = reterr[session]
    local ret = retmsg[session]
    reterr[session], retmsg[session] = nil, nil
    if err then return false, ret end
    return ret
end

local rpc_req_load
function client.initpush(rpc_req, host)
    if rpc_req_load then
        assert(rpc_req == rpc_req_load)
    else
        rpc_req_load = rpc_req
        local sprotoloader = require "sprotoloader"
        local protoloader = skynet.uniqueservice "protoloader"
        local slot = skynet.call(protoloader, "lua", "index", rpc_req)
        local sp = sprotoloader.load(slot)
        host = host or sp:host "package"
        sender = host:attach(sp)
    end
end

return client
