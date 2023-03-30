local skynet = require "skynet"
local lfs = require "lfs"
local log = require "log"
local logerr = require "log.err"
local net = require "robot.net"
local env = require "env"
local ustring = require "util.string"

require "robot.vminfo"

local _M = {}
local mods = {}
for file in lfs.dir(env.root .. "/lualib/robot/testcase/") do
    if file ~= "." and file ~= ".." then
        local pos = string.find(file, ".lua$")
        if pos then
            local name = string.sub(file, 1, pos - 1)
            local onlogin = assert(require("robot.testcase." .. name).onlogin)
            mods[name] = onlogin
            _M[name] = function(self)
                log("run robot.testcase." .. name)
                onlogin(self)
            end
        end
    end
end

local default_ignore = {battle = true}
function _M.default(self)
    local list = {}
    for nm in pairs(mods) do
        if not default_ignore[nm] then table.insert(list, nm) end
    end
    while #list > 0 do
        local r = math.random(1, #list)
        local nm = table.remove(list, r)
        local onlogin = mods[nm]
        log("run robot.testcase." .. nm)
        local ok, err = xpcall(onlogin, debug.traceback, self)
        if not ok then logerr(err) end
    end
end

local order = {
    "prepare", "pay", "recruit", "citytalent", "hero", "mainline", "guild"
}

function _M.inorder(self)
    for _, nm in ipairs(order) do
        local onlogin = mods[nm]
        log("run robot.testcase." .. nm)
        local ok, err = xpcall(onlogin, debug.traceback, self)
        if not ok then logerr(err) end

    end
end

require("robot.event").reg("onlogin", function(self)
    local testcases = ustring.split(env.testcase)
    local testnum = tonumber(env.testnum)
    if testnum == -1 then testnum = math.maxinteger end

    skynet.fork(function()
        while true do
            skynet.sleep(6000)
            -- local ret = 
            net.request(self, nil, 'ping', {any = skynet.hpc()}) -- s*1000000000
            -- local diff = (skynet.hpc() - ret.any) / 1000000 -- ms
            -- log("ping %03f ms", diff)
        end
    end)
    for _ = 1, testnum do
        skynet.sleep(100)
        for _, testcase in ipairs(testcases) do _M[testcase](self) end
    end
end)

return _M
