local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local utime = require "util.time"
local utable = require "util.table"

local insert = table.insert
local remove = table.remove

local CFG
skynet.init(function()
    CFG = cfgproxy("talk")
end)

local CONTENTS = {}

local _M = {}

function _M.get(tpname, channel)
    local contents = utable.getsub(CONTENTS, tpname, channel)
    local cfg = CFG[tpname]

    local expire_time = utime.time_int() - cfg.record_time
    while contents[1] and contents[1].time < expire_time do
        remove(contents, 1)
    end
    return contents
end

function _M.add(data, tpname, channel)
    local contents = utable.getsub(CONTENTS, tpname, channel)
    insert(contents, data)

    local cfg = CFG[tpname]
    local max = cfg.record_max
    assert(max > 0)
    while #contents > max do remove(contents, 1) end
end

function _M.init(contents, tpname, channel)
    local subccontent = utable.getsub(CONTENTS, tpname)
    subccontent[channel] = contents
end

function _M.del(tpname, channel)
    local subccontent = utable.getsub(CONTENTS, tpname)
    subccontent[channel] = nil
end

function _M.all(tpname)
    return CONTENTS[tpname] or {}
end

return _M
