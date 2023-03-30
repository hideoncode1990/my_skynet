local skynet = require "skynet"
local _LUA = require "handler.lua"
local log = require "log"
local guildmods = require "mods"()
local GUILD_PROXY
local _M = {}

skynet.init(function()
    GUILD_PROXY = skynet.uniqueservice("guild/proxy")
end)

function _M.call(cmd, ...)
    return skynet.call(GUILD_PROXY, "lua", cmd, ...)
end

function _M.send(cmd, ...)
    skynet.send(GUILD_PROXY, "lua", cmd, ...)
end

function _M.get_members(self)
    local ret = {}
    local gid = self.gid
    if not gid then return ret end
    local ok, _, info = _M.call("query_guild_detail", gid)
    if not ok then return ret end
    return info.members
end

function _M.in_guild(self)
    if self.gid and self.gid ~= 0 then return true end
    return false
end

function _M.reg(mod, nm)
    guildmods.reg(mod, nm)
end

local q = {}
local running
local function run_q()
    while next(q) do
        local ctx = table.remove(q, 1)
        guildmods.call(table.unpack(ctx))
    end
    running = nil
end

local function fork_run(fname, ...)
    table.insert(q, {fname, ...})
    if not running then
        running = true
        skynet.fork(run_q)
    end
end

function _M.load(self)
    fork_run("load", self)
end

function _M.enter(self)
    fork_run("enter", self)
end

function _M.leave(self)
    fork_run("leave", self)
end

local function wait_run(fname, ...)
    while running do skynet.sleep(10) end
    guildmods.call_revert(fname, ...)
end

function _M.unload(self)
    wait_run("unload", self)
end

function _M.retry(self)
    local ok, gid, gname = _M.call("retry", self.rid, skynet.self())
    if ok then fork_run("retry", self, gid, gname) end
end

function _LUA.guild_retry(self)
    _M.retry(self)
end

return _M
