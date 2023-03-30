local umods = require "mods"()
local _M = {}

function _M.enter(role)
    umods.call("enter", role)
end

function _M.leave(role)
    umods.call_revert("leave", role)
end

setmetatable(_M, {
    __call = function(_, m, name)
        umods.reg(m, name)
    end
})

return _M

