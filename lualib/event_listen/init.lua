local skynet = require "skynet"
local service = require "service"
local _R = require "handler.inner"
local log = require "log"
local autogc = require "autogc"
local pairs = pairs
local xpcall = xpcall
local traceback = debug.traceback
local next = next
local assert = assert
local table = table

local wait_list = {}
local sub_list = {}
local filters = require "event_listen.filter"

local function publish(ev_cb, ...)
    local ls = sub_list[ev_cb]
    if ls then
        local p = table.pack(...)
        for uniq_id, addr in pairs(ls) do
            if "function" == type(p[1]) then
                local callback = p[1]
                skynet.fork(function()
                    callback(skynet.call(addr, "inner", "subscribe_return",
                                         uniq_id, table.unpack(p, 2)))
                end)
            else
                skynet.send(addr, "inner", "subscribe_return", uniq_id, ...)
            end
        end
    end
    ls = wait_list[ev_cb]
    if ls then
        for resp, args in pairs(ls) do
            local cb = filters[ev_cb]
            local ok, ret = xpcall(cb, traceback, resp, args, ...)
            if ret then ls[resp] = nil end
            if not ok then log(ret) end
        end
        if not next(ls) then wait_list[ev_cb] = nil end
    end
end

local function subscribe(ev_cb, addr, uniq_id)
    -- assert(filters[ev_cb])
    local ls = sub_list[ev_cb]
    if not ls then
        ls = {}
        sub_list[ev_cb] = ls
    end
    ls[uniq_id] = addr
end

local function unsubscribe(ev_cb, uniq_id)
    local ls = sub_list[ev_cb]
    if ls then
        local addr = ls[uniq_id]
        if addr then
            ls[uniq_id] = nil
            if not next(ls) then sub_list[ev_cb] = nil end
        end
    end
end

local function wait(ev_cb, args)
    assert(filters[ev_cb])
    local ls = wait_list[ev_cb]
    if not ls then
        ls = {}
        wait_list[ev_cb] = ls
    end
    ls[skynet.response()] = args or {}
end

function _R.event_subscribe(addr, uniq_id, ev_cb)
    subscribe(ev_cb, addr, uniq_id)
end

function _R.event_unsubscribe(uniq_id, ev_cb)
    unsubscribe(ev_cb, uniq_id)
end

function _R.event_wait(ev_cb, ...)
    wait(ev_cb, ...)
    return service.NORET
end

autogc.rereg("event_listen_resp", function()
    for ev_cb, ls in pairs(wait_list) do
        for resp, args in ipairs(ls) do resp(false, "destorty") end
    end
end)

return publish
