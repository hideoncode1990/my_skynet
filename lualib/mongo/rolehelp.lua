local skynet = require "skynet"
local collection = "player"
local base_field = {
    rid = true,
    rname = true,
    sid = true,
    uid = true,
    created = true
}

local _M = {}

function _M.select(proxy, uid, sid)
    return skynet.call(proxy, "lua", "findone", collection,
        {uid = uid, sid = sid}, base_field)
end

function _M.select_byargs(proxy, args, field, skip, limit)
    return skynet.call(proxy, "lua", "findall", collection, args,
        field or base_field, skip, limit)
end

function _M.update(proxy, selector, update)
    return skynet.call(proxy, "lua", "update", collection, selector, update,
        false, false)
end

function _M.find(proxy, rid)
    return skynet.call(proxy, "lua", "findone", collection, {rid = rid},
        base_field)
end

return _M
