local utime = require "util.time"
local skiplist = require "skiplist.c"
local log = require "log"

local LRU = skiplist()

local _M = {}

local TOUCH = {}

function _M.mark(uuid)
    local now = utime.time_int()
    local touch = TOUCH[uuid]
    if touch then
        if now - touch > 1 then
            LRU:delete(touch, uuid)
            TOUCH[uuid] = nil
            touch = nil
        end
    end
    if not touch then
        LRU:insert(now, uuid)
        TOUCH[uuid] = now
        -- log("REPLAY_MEMO LRU touch %s %s", uuid, now)
    end
end

function _M.del(uuid, why)
    local touch = assert(TOUCH[uuid])
    TOUCH[uuid] = nil
    LRU:delete(touch, uuid)
    -- log("REPLAY_MEMO LRU del %s %s %s", uuid, touch, why)
end

function _M.get_head()
    local uuid = LRU:get_rank_range(1, 1)[1]
    return uuid, TOUCH[uuid]
end

function _M.clean()
    return LRU:delete_by_rank(0, LRU:get_count() - 1, function(uuid)
        _M.del(uuid, "clean")
    end)
end

function _M.timeout_list(ti)
    return LRU:get_score_range(0, ti)
end

function _M.get_count()
    return LRU:get_count()
end

return _M
