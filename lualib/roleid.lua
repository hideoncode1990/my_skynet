local _M = {}

local sid_shift<const> = 16

function _M.genrid(sid, val)
    local rid = (sid << sid_shift) | val
    return rid
end

function _M.getsid(rid)
    local sid = rid >> sid_shift
    return sid
end

local shift_mask<const> = (1 << 16) - 1
function _M.getval(rid)
    return shift_mask & rid
end

return _M
