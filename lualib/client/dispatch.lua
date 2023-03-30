local client = require "client"
local skynet = require "skynet"
local socketdriver = require "skynet.socketdriver"
local profile = require "skynet.profile"
local log = require "log"

local host
local control = require "client.control"
local handler = require "handler.client"
require "client.control.forbidden"

local service_name = _G.SERVICE_NAME
local enable_profile = true
local profiled
skynet.init(function()
    profiled = skynet.uniqueservice("base/profiled")
end)

local xpcall = xpcall
local string = string
local traceback = debug.traceback
local controlcheck = control.check

local function retclient(fd, response, result, name)
    if response and fd then
        local msg = string.pack(">s2", response(result))
        if not socketdriver.send(fd, msg) then
            log("response %s failure", name)
        end
    end
end

local function execute(self, fd, f, name, args, response)
    local result = f(self, args)
    retclient(fd, response, result, name)
end

local function handle_msg(self, fd, f, name, args, response)
    local enable = enable_profile
    if enable then profile.start() end
    local ok, result = controlcheck(self, name)
    if ok then
        ok, result = pcall(retclient, traceback, fd, response, result, name)
    else
        ok, result = xpcall(f, traceback, self, args)
        if ok then
            ok, result = pcall(retclient, fd, response, result, name)
        else
            pcall(retclient, fd, response, {e = 0xffff - 1}, name)
        end
    end
    if not ok then log("raise error = %s", result) end
    if enable then
        skynet.send(profiled, "lua", "stat", service_name .. "." .. name,
            profile.stop())
    end
end

function client.dispatch(self, fd, msg, sz)
    if fd ~= self.fd then
        log("dispatch errfd %s %s", tostring(fd), tostring(self.fd))
        return
    end
    local type, name, args, response = host:dispatch(msg, sz)
    if type == "REQUEST" then
        local f = handler[name]
        if f then
            handle_msg(self, fd, f, name, args, response)
        else
            error("Invalid command " .. name)
        end
    else
        local session, result, _ = name, args, response
        client.response(session, result)
    end
end

function client.dispatch_once(self, fd, handlers, msg, sz)
    local type, name, args, response = host:dispatch(msg, sz)
    assert(type == "REQUEST", "dispatch_special " .. name)
    local f = assert(handlers[name])
    handlers[name] = nil
    execute(self, fd, f, name, args, response)
end

function client.initrpc(rpc_run)
    local sprotoloader = require "sprotoloader"
    local protoloader = skynet.uniqueservice "protoloader"
    local slot = skynet.call(protoloader, "lua", "index", rpc_run)
    host = sprotoloader.load(slot):host "package"
    return host
end

function client.init(rpc_run, rpc_req)
    client.initpush(rpc_req, client.initrpc(rpc_run))
end

function client.profile(enable)
    enable_profile = enable
end

return client
