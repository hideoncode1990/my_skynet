local skynet = require "skynet"
local cluster = require "skynet.cluster"
local uniq = require "uniq.c"
local env = require "env"
local selfnode = env.node

local _M = {}

local function unref(self)
    local uuid = self.uuid
    if uuid then
        self.uuid = nil
        cluster.send(self.node, "@refd", "nodeunref", selfnode, uuid)
    end
end

local _MT = {__close = unref, __gc = unref}

local function ref(siteaddr, wait)
    local uuid = uniq.uuid()
    local node, addr = siteaddr.node, siteaddr.addr
    local ok, err = cluster.call(node, "@refd", "noderef", selfnode, addr, uuid,
        wait)
    if ok then
        return setmetatable({node = node, uuid = uuid}, _MT)
    else
        return ok, err
    end
end

_M.ref = ref
_M.unref = unref

return _M
