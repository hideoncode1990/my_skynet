local skynet = require "skynet"
local uniq = require "uniq.c"
local utime = require "util.time"
local lang = require "lang"

local _M = {}

local emailpost
skynet.init(function()
    emailpost = skynet.uniqueservice('game/emailpost')
end)

function _M.send(e)
    e.id = uniq.uuid()
    assert(e.target)
    e.theme = e.theme or ""
    e.content = e.content or ""
    assert(e.option)
    e.time = utime.time()
    local items = e.items
    if items and #items == 0 then e.items = nil end
    e.readtime = 0
    e.signer = e.signer or lang("SIGNER_DEAULT")

    skynet.send(emailpost, "lua", "post", e)
end

return _M
