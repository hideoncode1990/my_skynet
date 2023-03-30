local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"

local net = require "robot.net"
local _H = require "handler.client"
local log = require "robot.log"
local fnopen = require "robot.fnopen"

local CFG
skynet.init(function()
    CFG = cfgproxy("recruit")
end)

local NM<const> = "recruit"
local default_feature

function _H.recruit_info(self, msg)
    default_feature = msg.default_feature
end

local function execute(self)
    for i = 1, 5 do
        if default_feature then
            for tp in pairs(CFG) do
                local feature = tp == 2 and default_feature or nil
                local ret = net.request(self, 100, "recruit_ten",
                    {type = tp, feature = 1})
                log(self, {
                    opt = "recruit",
                    type = tp,
                    feature = feature,
                    e = ret and ret.e or ret
                })
                skynet.sleep(30)
            end
        end
    end
end

return {
    onlogin = function(self)
        if fnopen.check(self, NM) then execute(self) end
    end
}

