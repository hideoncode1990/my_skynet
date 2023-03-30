local getupvalue = require "debug.getupvalue"
local _LUA = require "handler.lua"
local _H = require "handler.client"

function _LUA.client(self, cmd, ...)
    return _H[cmd](self, ...)
end

function _LUA.client_enter(self)
    local LUA_enter = _LUA.enter
    local enter, rolelock = getupvalue(LUA_enter, "enter", "rolelock")
    rolelock(enter, self, {})
end

function _LUA.client_afk(self)
    local LUA_afk = _LUA.afk
    local on_afk, rolelock = getupvalue(LUA_afk, "on_afk", "rolelock")
    rolelock(function()
        if not self.fd and self.STATE == 3 then
            self.fd = -1
            on_afk(self, -1)
        end
    end)
end
