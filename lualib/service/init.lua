local skynet = require "skynet"
local profile = require "skynet.profile"
local _M = require "service.release"

local service_name = _G.SERVICE_NAME
local enable_profile = true
local profiled
skynet.init(function()
    profiled = skynet.uniqueservice("base/profiled")
end)

_M.NORET = {}

local function add_stop_cmd(funcs, release)
    assert(not funcs.stop, "use release replace stop")
    assert(not funcs.watch_live, "watch_live is a system command")
    if release then _M.release("add_stop_cmd", release) end
    local WAIT_QUIT
    funcs.stop = function()
        if WAIT_QUIT then
            local co = coroutine.running()
            table.insert(WAIT_QUIT, co)
            skynet.wait(co)
        else
            WAIT_QUIT = {}
            _M.releaseall()
            for _, co in pairs(WAIT_QUIT) do skynet.wakeup(co) end
            skynet.fork(skynet.exit) -- //wakeup queue run before fork queue
        end
    end
    funcs.watch_live = function()
        skynet.response()
        return _M.NORET
    end
    funcs.ping = function()
    end
end

local function ret(r, ...)
    if r ~= _M.NORET then
        return skynet.retpack(r, ...)
    else
        skynet.ignoreret()
    end
end

_M.ret = ret

function _M.dispatch(proto, funcs)
    local dispatch = function(session, _, cmd, ...)
        local f = funcs[cmd]
        if f then
            local enable = enable_profile
            if enable then profile.start() end
            if session > 0 then
                ret(f(...))
            else
                f(...)
            end
            if enable then
                skynet.send(profiled, "lua", "stat", service_name .. "." .. cmd,
                    profile.stop())
            end
        else
            skynet.error("Unknown command : ", proto, cmd)
            skynet.response()(false)
        end
    end
    skynet.dispatch(proto, dispatch)
    return dispatch
end

function _M.start(mod)
    enable_profile = not mod.disable_profile
    local info = mod.info or mod
    if type(info) ~= "function" then
        _M.info = function()
            return info
        end
    else
        _M.info = info
    end
    skynet.info_func(_M.info)

    local _LUA = require "handler.lua"
    add_stop_cmd(_LUA, mod.release)

    local dispatch = mod.dispatch or {}
    if not dispatch.lua then _M.dispatch("lua", _LUA) end
    for name, call in pairs(dispatch) do skynet.dispatch(name, call) end
    skynet.start(function()
        if mod.init then mod.init() end
        if mod.regquit then _M.regquit() end
        if mod.master then
            skynet.send(skynet.uniqueservice("base/masterd"), "lua", "reg",
                mod.master)
        end
    end)
end

return _M
