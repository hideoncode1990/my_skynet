local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local words = require "words"
local ext = require "ext.c"

local BASIC
skynet.init(function()
    BASIC = cfgproxy("basic")
end)

return function(oname, limit)
    local name = ext.name_trim(oname)
    limit = limit or BASIC.name_limit
    local len = utf8.len(name)
    if len < limit[1] or len > limit[2] then return false, 1 end
    if name == "" then return name end
    if not words.namecheck(name) then return false, 2 end
    return name
end
