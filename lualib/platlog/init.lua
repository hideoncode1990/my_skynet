local utime = require "util.time"
local skynet = require "skynet"
local log_t = require "platlog.code"
local env = require "env"
local unique = require "service.unique"

return function(log_name, d, self, log_ti)
    if env.enable_platlog == "false" then return end

    local modulecode = log_t[log_name]
    if not modulecode then error("platlog cannot support fmt:" .. log_name) end
    local ti = log_ti or utime.time_int()
    d.event_time = os.date("%Y-%m-%d %X", ti)
    d.app_id = "6847930183176796"
    d.log_name = log_name
    d.step_num_id = d.step_num_id or modulecode
    d.server_id = env.node_id
    if self then
        d.version = self.version
        d.game_channel = self.game_channel
        d.user_id = tostring(self.uid)
        d.role_id = tostring(self.rid or d.role_id or "null")
        d.role_name = self.rname or d.role_name or "null"
        d.role_level = self.level
        d.power = self.zdl or 0
        d.faction_id = d.faction_id or tostring(self.gid or 0)
        d.device_id = self.device_id
        d.player_friends_num = self.friendcnt or 0
        d.ip = d.ip or self.ip
        d.vip = tostring(self.viplevel or 0)
    end
    skynet.send(unique["game/platlog/main"], "lua", "add", log_name, ti, d)
end
