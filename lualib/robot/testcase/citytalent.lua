local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"

local net = require "robot.net"
local _H = require "handler.client"
local mainline = require "robot.testcase.mainline"
local fnopen = require "robot.fnopen"

local NM<const> = "citytalent"

local NM1<const> = NM .. "1"
local NM2<const> = NM .. "2"

local CFG
skynet.init(function()
    CFG = cfgproxy("citytalent")
end)

local C
function _H.citytalent_info(_, msg)
    C = msg
end

local function try(self)
    for id, cfgs in pairs(CFG) do
        local tp = cfgs.type
        if fnopen.check(self, "citytalent" .. tp) and mainline.query(self) >=
            cfgs.mainline then
            while true do
                local level = C[id] or 0
                local tlevel = level + 1
                local cfg = cfgs[level]
                if cfg then
                    local condition = cfg.condition
                    if condition then
                        local cid, clevel = condition[1], condition[2]
                        if (C[cid] or 0) < clevel then
                            break
                        end
                    end

                    local ret = net.request(self, 100, "citytalent_levelup",
                        {id = id, level = level})
                    local e = ret and ret.e
                    if e == 0 then
                        C[id] = tlevel
                        skynet.sleep(100)
                    else
                        break
                    end
                else
                    break
                end
            end
        end
    end
end

return {
    onlogin = function(self)
        if fnopen.check(self, NM1) or fnopen.check(self, NM2) then
            try(self)
        end
    end
}
