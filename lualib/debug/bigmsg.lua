local skynet = require "skynet"

local _H = require "handler.client"

local DATA = {}

local function wakeup(session, err)
    local tbs = DATA[session]
    if not tbs then return end
    DATA[session] = nil
    if err then tbs.err = err end
    skynet.wakeup(tbs)
end

function _H.debug_longstring(_, msg)
    local session, data = msg.session, msg.data
    local tbs = DATA[session]
    if not tbs then return end
    table.insert(tbs, data)
    if #tbs > 100 then wakeup(session, "bigmsg too big") end
end

function _H.debug_longstring_over(_, msg)
    local session, data = msg.session, msg.data
    local tbs = DATA[session]
    if not tbs then return end
    table.insert(tbs, data)
    wakeup(session)
end

local _M = {}

function _M.wait(session, ti)
    assert(not DATA[session])
    local list = {}
    DATA[session] = list
    skynet.timeout(ti, function()
        wakeup(session, "timeout")
    end)
    skynet.wait(list)
    local err = list.err
    if not err then
        DATA[session] = nil
        return table.concat(list)
    else
        return false, err
    end
end

return _M
