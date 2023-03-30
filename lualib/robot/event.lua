local parallels = require "parallels"
local skynet = require "skynet"
local _M = {}

local CBS = setmetatable({}, {
    __index = function(t, k)
        local v = {}
        t[k] = v
        return v
    end
})

function _M.reg(type, cb)
    table.insert(CBS[type], cb)
end

function _M.occur(type, ...)
    for _, cb in pairs(CBS[type]) do skynet.fork(cb, ...) end
end

function _M.occur_wait(type, ...)
    local pa = parallels()
    for _, cb in ipairs(CBS[type]) do pa:add(cb, ...) end
    pa:wait()
end

return _M
