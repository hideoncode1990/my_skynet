local insert = table.insert

local _M = {}
local _LUA = require "handler.lua"

local CALL, CACHE, LIST = {}, {}, nil

function _M.reg(nm, cb)
    assert(not CALL[nm])
    CALL[nm] = cb
end

function _M.dirty(_, nm)
    CACHE[nm] = nil
    LIST = nil
end

function _M.get(self)
    local ret = LIST
    if ret then return ret end
    ret = {}
    for nm, cb in pairs(CALL) do
        local list = CACHE[nm]
        if not list then
            list = cb(self)
            CACHE[nm] = list
        end
        for _, effect in ipairs(list) do insert(ret, effect) end
    end
    LIST = ret
    return ret
end

_LUA.passive_get = _M.get

return _M
