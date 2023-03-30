local _M = {}
function _M.map_end(resp)
    -- if args.hp then
    local ret = {}
    resp(true, ret)
    return true
end

return _M

