local hero = require "hero"
local flowlog = require "flowlog"

local utime = require "util.time"

local _H = require "handler.client"

function _H.lock_set(self, msg)
    local uuid = msg.uuid
    if not hero.update_lock(self, uuid, utime.time()) then return {e = 2} end
    flowlog.role_act(self, {flag = "lock_set", arg1 = uuid})
    return {e = 0, uuid = uuid}
end

function _H.lock_cancle(self, msg)
    local uuid = msg.uuid
    if not hero.update_lock(self, uuid, false) then return {e = 2} end
    flowlog.role_act(self, {flag = "lock_cancle", arg1 = uuid})
    return {e = 0, uuid = uuid}
end

local _M = {}
function _M.check(self, uuid)
    return hero.query(self, uuid).lock
end

return _M
