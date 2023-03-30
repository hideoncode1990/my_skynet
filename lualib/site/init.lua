local skynet = require "skynet"
local cluster = require "skynet.cluster"
local format = string.format
local type = type
local env = require "env"
local _M = {}

local NODE = env.node
_M.node = NODE

local function addr2string(t)
    local addr = t.addr
    if type(addr) == "number" then
        return format("%s(%08x)", t.node, addr)
    else
        return format("%s(%s)", t.node, addr)
    end
end

local tostring_mt = {__tostring = addr2string}

local self_siteaddr = setmetatable({node = NODE, addr = skynet.self()},
    tostring_mt)

function _M.tostring(t)
    return addr2string(t)
end

function _M.service(name)
    cluster.register(name)
    self_siteaddr.addr = '@' .. name
end

function _M.addr_build(addr)
    return {addr = addr, node = NODE}
end

function _M.addr_copy(addr)
    return {addr = addr.addr, node = addr.node}
end

function _M.addr_tryself(siteaddr)
    if siteaddr.node == NODE then
        local addr = siteaddr.addr
        if type(addr) ~= "number" then
            siteaddr.addr = cluster.queryname(addr) or addr
        end
        return true
    end
end

function _M.self()
    return self_siteaddr
end

function _M.send(siteaddr, ...)
    local node, addr = siteaddr.node, siteaddr.addr
    if node == NODE and type(addr) == "number" then
        skynet.send(addr, "lua", ...)
    else
        cluster.send(node, addr, ...)
    end
end

function _M.call(siteaddr, c, ...)
    local node, addr = siteaddr.node, siteaddr.addr
    if node == NODE and type(addr) == "number" then
        return skynet.call(addr, "lua", c, ...)
    else
        return cluster.call(node, addr, c, ...)
    end
end

function _M.same_addr(left, right)
    if not left or not right then return end
    _M.addr_tryself(left)
    _M.addr_tryself(right)
    return left.node == right.node and left.addr == right.addr
end

_M.addr_tostring = addr2string

return _M
