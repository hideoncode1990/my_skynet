local skynet = require "skynet"
local ustring = require "util.string"
local cfgproxy = require "cfg.proxy"

local CFG
skynet.init(function()
    CFG = cfgproxy("lang")
end)

--- @param fmt string
--- @return string
return function(fmt, ...)
    local _fmt = CFG[fmt] or fmt
    return ustring.strfmt(_fmt, ...)
end
