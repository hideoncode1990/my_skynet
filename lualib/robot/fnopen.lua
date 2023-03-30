local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"

local _H = require "handler.client"
local _M = {}

local CFG
skynet.init(function()
    CFG = cfgproxy("fnopen")
end)

local CALL, OPENLIST = {}, {}

local function whenfnopen(self, ids, need)
    for _, id in ipairs(ids) do
        local cfg = assert(CFG.fnopen[id])
        local mark = cfg.mark
        OPENLIST[id], OPENLIST[mark] = true, true
        local call = CALL[mark]
        if call and need then skynet.fork(call, self) end
    end
end

function _H.fnopen_list(self, msg)
    -- pdump(msg, "fnopen_list")
    whenfnopen(self, msg.ids)
end

function _H.fnopen_new(self, msg)
    whenfnopen(self, msg.ids, true)
end

function _M.check(_, mark)
    return OPENLIST[mark]
end

return _M
