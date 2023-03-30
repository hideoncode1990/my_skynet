local HEROBEST, DICT
local log = require "robot.log"

local _M = {}
local _H = require "handler.client"

function _H.herobest_list(self, msg)
    HEROBEST = msg.list
    local dict = {}
    for pos, uuid in ipairs(HEROBEST) do dict[uuid] = pos end
    DICT = dict
    log(self, {opt = "herobest_list"})
end

function _M.query(self)
    return HEROBEST, DICT
end
return _M
