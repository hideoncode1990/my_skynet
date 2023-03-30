local replay = require "replay"
local gamesid = require "game.sid"
local _M = {}
local CB = {}
local _H = require "handler.client"

function _M.reg(ttype, cb)
    assert(not CB[ttype])
    CB[ttype] = cb
end

function _H.report(self, msg)
    local ttype, key, replayid = msg.type, assert(msg.key), msg.replayid
    local cb = CB[ttype]
    local report = cb(self, key, replayid)
    if not report then return {e = 1} end
    return {e = 0, report = report}
end

local function getsid(replayid)
    return replayid >> (29 + 19)
end

function _H.report_replay(self, msg)
    local replayid = msg.replayid
    local sid = getsid(tonumber(replayid))
    local ok, err
    local player = {rid = self.rid, fd = self.fd, addr = self.addr}
    if gamesid[sid] then
        ok, err = replay.play(msg.replayid, player)
    else
        ok, err = replay.play_remote(replayid, player, "game_" .. sid)
    end
    if not ok then return {e = err} end
    return {e = 0}
end

return _M
