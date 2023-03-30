local net = require "robot.net"
local _H = require "handler.client"
local fnopen = require "robot.fnopen"

local log = require "log"
require "util"

local NM<const> = "guild"
local _M = {}

function _H.guild_info(self, msg)
    self.gid = msg.info.gid
    self.guild_contribution = msg.info.contribution
    for rid, mem in pairs(msg.info.members) do
        if rid == self.rid then self.guild_pos = mem.pos end
    end
end

local function get_guildlist(self)
    local ret = net.request(self, 100, "guild_search", {name = "bot"})
    return ret.list
end

local function check_join(self)
    local list = get_guildlist(self)
    if not list then return false end
    for _, guild in pairs(list) do
        if guild.num < 30 then return true, guild.gid end
    end
    return true
end

local function create_guild(self)
    local ret = net.request(self, 100, "guild_create",
        {icon = 1, name = "bot" .. math.random(9999)})
    log("%s create guild e=%d", self.rname, ret.e)
end

local function join_guild(self, gid)
    local ret = net.request(self, 100, "guild_apply", {gid = gid})
    log("%s join guild e=%d", self.rname, ret.e)
end

function _M.onlogin(self)
    if fnopen.check(self, NM) then
        if not self.gid then
            local ok, gid = check_join(self)
            print(self.rname, ok, gid)
            if not ok then return end
            if gid then
                join_guild(self, gid)
            else
                create_guild(self)
            end
        end
    end
end

return _M
