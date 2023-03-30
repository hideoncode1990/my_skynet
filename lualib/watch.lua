local skynet = require "skynet"
local site = require "site"
local logerr = require "log.err"
local _INNER = require "handler.inner"

local watchd
skynet.init(function()
    watchd = skynet.uniqueservice("base/watchd")
end)

local watch = {}

local function addwatch(self, uuid, node, addr)
    local ws = watch[uuid]
    if ws then
        table.insert(ws, self)
    else
        ws = {self}
        watch[uuid] = ws
        skynet.send(watchd, "lua", "watch", skynet.self(), node, addr)
    end
end

local function removewatch(self, uuid, node, addr)
    local ws = watch[uuid]
    if not ws then return end

    for idx, w in ipairs(ws) do
        if w == self then
            table.remove(ws, idx)
            if #ws == 0 then
                watch[uuid] = nil
                skynet.send(watchd, "lua", "unwatch", skynet.self(), node, addr)
            end
            return true
        end
    end
end

local function watch_return_one(self)
    local co, cb, args = self.co, self.cb, self.args
    self.uuid, self.co, self.node, self.addr, self.cb, self.args = nil, nil,
        nil, nil, nil, nil
    if co then skynet.wakeup(co) end
    if cb then skynet.fork(cb, table.unpack(args)) end
end

local mt_gc = function(t)
    local uuid, node, addr = t.uuid, t.node, t.addr
    if uuid then
        assert(removewatch(t, uuid, node, addr))
        watch_return_one(t)
    end
end

local _M = {}

local mt = {__gc = mt_gc, __index = _M}

local function new()
    local self = {}
    return setmetatable(self, mt)
end

function _M.watch(self, siteaddr)
    assert(not self.uuid and siteaddr)
    local node, addr = siteaddr.node, siteaddr.addr
    local uuid = site.addr_tostring(siteaddr)
    local co = coroutine.running()
    self.co = co
    self.uuid = uuid
    self.node = node
    self.addr = addr
    addwatch(self, uuid, node, addr)
    skynet.wait(co)
end

function _M.watchnode(self, node)
    return _M.watch(self, {node = node, addr = "@watchd"})
end

function _M.connect(_, node, noblock)
    return skynet.call(watchd, "lua", "connect", node, noblock)
end

function _M.start(self, siteaddr, aftercb, ...)
    local ok, err = xpcall(aftercb, debug.traceback, self, ...)
    if not ok then
        logerr(err)
        skynet.sleep(100)
    else
        _M.watch(self, siteaddr)
    end
end

function _M.isok(self)
    return self.uuid ~= nil
end

function _M.callback(self, siteaddr, cb, ...)
    assert(not self.uuid and siteaddr)
    local node, addr = siteaddr.node, siteaddr.addr
    local uuid = site.addr_tostring(siteaddr)
    self.uuid = uuid
    self.node = node
    self.addr = addr
    self.cb = cb
    self.args = table.pack(...)
    addwatch(self, uuid, node, addr)
end

function _M.unwatch(self)
    mt_gc(self)
end

function _INNER.watch_return(node, addr)
    local uuid = site.addr_tostring({node = node, addr = addr})
    local ws = watch[uuid]
    if ws then
        watch[uuid] = nil
        for _, self in ipairs(ws) do watch_return_one(self) end
    end
end

return new
