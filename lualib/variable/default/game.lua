local utime = require "util.time"
local gamesid = require "game.sid"
local env = require "env"

local node_id = tonumber(env.node_id)
return function()
    local r = {
        online_max = {value = 10000, type = "integer", desc = "最大在线"},
        enterqueue_max = {
            value = 10000,
            type = "integer",
            desc = "排队人数"
        },
        enterqueue_speed = {
            value = 100,
            type = "integer",
            desc = "进入游戏人数(秒)"
        },
        clientcontrol = {value = {}, desc = "禁止客户端消息"},
        role_max = {
            value = 3000,
            type = "integer",
            desc = "最大创建角色数量"
        }
    }
    for sid in pairs(gamesid) do
        r["starttime_" .. sid] = {
            value = utime.time_int(),
            type = "integer",
            desc = "开服时间"
        }
    end
    local alise = {server_starttime = "starttime_" .. node_id}

    return r, alise
end
