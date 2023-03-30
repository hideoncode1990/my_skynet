local skynet = require "skynet"
local logerr = require "log.err"

local service_name = _G.SERVICE_NAME
local releases = {}
local _M = {}
function _M.release(nm, call)
    assert(nm and call)
    for _, node in ipairs(releases) do
        if node[1] == nm then
            node[2] = call
            logerr("release call[%s] replaced", nm)
            call = nil
            break
        end
    end
    if call then table.insert(releases, 1, {nm, call}) end
end

function _M.releaseall()
    for _, node in ipairs(releases) do
        local ok, err = pcall(node[2])
        if not ok then logerr(err) end
    end
end

local regquit
function _M.regquit(force)
    if not regquit or force then
        regquit = true
        local mgr = skynet.uniqueservice("quitmgr")
        skynet.send(mgr, "lua", "reg", skynet.self(), service_name)
    end
end

return _M
