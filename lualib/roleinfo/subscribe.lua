local skynet = require "skynet"
local _IN = require "handler.inner"

local roleinfoproxy
skynet.init(function()
    roleinfoproxy = skynet.uniqueservice("game/roleinfoproxy")
end)

local _M = {}
local CBLIST = {}

local MT = {
    __gc = function(t)
        local rid = t.rid
        if rid then
            t.rid = nil
            local list = CBLIST[rid]
            for idx, sb in ipairs(list) do
                if t == sb then
                    table.remove(list, idx)
                    if #list == 0 then
                        CBLIST[rid] = nil
                        skynet.send(roleinfoproxy, "lua", "unsubscribe", rid,
                            skynet.self())
                    end
                    break
                end
            end
        end
    end
}

function _M.subscribe(cb, rid)
    local sb = setmetatable({cb = cb, rid = rid}, MT)
    local list = CBLIST[rid]
    if not list then
        list = {sb}
        CBLIST[rid] = list
        skynet.send(roleinfoproxy, "lua", "subscribe", rid, skynet.self())
    else
        table.insert(list, sb)
    end
    return sb
end

function _M.unsubscribe(sb)
    MT.__gc(sb)
end

function _IN.roleinfo_change(rid, data)
    local list = CBLIST[rid]
    if not list then return end
    for _, sb in ipairs(list) do skynet.fork(sb.cb, data, rid) end
end

return _M
