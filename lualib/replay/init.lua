local skynet = require "skynet"
local limit_t = require "battle.limit"

local _M = {}

local replayd, replay_playd
skynet.init(function()
    replayd = skynet.uniqueservice("game/replayd")
end)

function _M.add(rep)
    return skynet.send(replayd, "lua", "add", rep)
end

function _M.play(uuid, ply) -- ply = {rid = rid, fd = fd,addr = addr}
    replay_playd = replay_playd or skynet.uniqueservice("game/replay_playd")
    return skynet.call(replay_playd, "lua", "play", uuid, ply)
end

function _M.play_remote(uuid, ply, node)
    replay_playd = replay_playd or skynet.uniqueservice("game/replay_playd")
    return skynet.call(replay_playd, "lua", "play_remote", uuid, ply, node)
end

function _M.play_center(uuid, ply, name)
    replay_playd = replay_playd or skynet.uniqueservice("game/replay_playd")
    return skynet.call(replay_playd, "lua", "play_center", uuid, ply, name)
end

function _M.limit_filter(limit)
    -- replay禁止自动战斗和使用技能
    limit = limit & (~limit_t.terminate)
    limit = limit & (~limit_t.pause)
    limit = limit | limit_t.auto
    limit = limit | limit_t.manual
    return limit
end

function _M.check_and_del_expire(expire_time)
    skynet.send(replayd, "lua", "check_and_del_expire", expire_time)
end

function _M.query(uuid)
    return skynet.call(replayd, "lua", "query", "query", uuid)
end
return _M
