local _M = {}
local _SAVE = {}

local setmetatable = setmetatable

local function call_gc(t)
    local __gc = t.__gc
    if __gc then
        t.__gc = nil
        __gc()
    end
end

local mt = {__gc = call_gc}

function _M.reg(name, call)
    assert(not _SAVE[name])
    _SAVE[name] = setmetatable({__gc = call}, mt)
    return _M
end

function _M.release(name)
    local o = _SAVE[name]
    if o then
        _SAVE[name] = nil
        setmetatable(o, nil)
        call_gc(o)
    end
    return _M
end

function _M.cancel(name)
    local o = _SAVE[name]
    if o then
        _SAVE[name] = nil
        setmetatable(o, nil)
    end
    return _M
end

function _M.replace(name, call)
    return _M.release(name).reg(name, call)
end

function _M.rereg(name, call)
    return _M.cancel(name).reg(name, call)
end

return _M
