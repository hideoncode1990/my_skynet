local skynet = require "skynet"

local refd
skynet.init(function()
    refd = skynet.uniqueservice("base/refd")
end)

local _M = {}

local function unref(self)
    local addr = self.addr
    if addr then
        self.addr = nil
        skynet.send(refd, "lua", "unref", addr)
    end
end

local _MT = {__close = unref}

local function ref(addr, wait)
    local ok, err = skynet.call(refd, "lua", "ref", addr, wait)
    if ok then
        return setmetatable({addr = addr}, _MT)
    else
        return ok, err
    end
end

_M.ref = ref
_M.unref = unref

function _M.addr(self)
    return self.addr
end

return _M
