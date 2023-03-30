local pairs = pairs
local _M = {}

local cbs = {}

function _M.check(self, msg_name)
    for _, cb in pairs(cbs) do
        local ret = cb(self, msg_name)
        if ret then return true, ret end
    end
end

function _M.reg(name, cb)
    cbs[name] = cb
end

return _M
