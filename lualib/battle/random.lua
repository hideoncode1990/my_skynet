local _M = {}
function _M.rand(bctx)
    local random = bctx.random
    return random()
end

function _M.setseed(seed)
    local rand = seed or 1
    return function()
        rand = ((rand * 214013 + 25310112) >> 16) & 0x7fff
        return rand
    end
end

return _M
