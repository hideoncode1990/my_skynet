local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"

local insert = table.insert
local remove = table.remove

local CFG
skynet.init(function()
    CFG = cfgproxy("talk_common")
end)

local _M = {}

local QUEUE = {}
local cntps = 10

local INSEND

local CNT = 0
local function chat_send(cb)
    local i = 0
    local para = CFG.info_limit / cntps
    while QUEUE[1] do
        i = i + 1
        CNT = CNT + 1
        local data = QUEUE[1]
        remove(QUEUE, 1)
        cb(data)

        if i == para then
            i = 0
            skynet.sleep(100 / cntps)
        else
            i = i + 1
        end
    end
    INSEND = nil
end

local time, n = 0, 0
function _M.add(tp, data, cb)
    if #QUEUE >= CFG.cache_limit then return false, tp * 100 + 8 end
    if data.time == time then
        n = n + 1
        assert(n < 100000)
        data.time = data.time + (n / 100000)
    else
        time = data.time
        n = 0
    end
    insert(QUEUE, data)
    if INSEND then return true end
    INSEND = true
    skynet.fork(chat_send, cb)
    return true
end

function _M.get_cnt()
    local cnt = CNT
    CNT = 0
    return cnt
end

return _M
