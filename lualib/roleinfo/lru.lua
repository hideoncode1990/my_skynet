local utime = require "util.time"
local skiplist = require "skiplist.c"

local LRU = skiplist()

local _M = {}

local TOUCH = {}

function _M.mark(rid)
    local now = utime.time_int()
    local touch = TOUCH[rid]
    if touch then
        if now - touch > 1 then
            LRU:delete(touch, rid)
            TOUCH[rid] = nil
            touch = nil
        end
    end
    if not touch then
        LRU:insert(now, rid)
        TOUCH[rid] = now
    end
end

function _M.del(rid, why)
    local touch = assert(TOUCH[rid])
    TOUCH[rid] = nil
    LRU:delete(touch, rid)
end

function _M.get_head()
    local rid = LRU:get_rank_range(1, 1)[1]
    return rid, TOUCH[rid]
end

function _M.clean()
    return LRU:delete_by_rank(0, LRU:get_count() - 1, function(rid)
        _M.del(rid, "clean")
    end)
end

function _M.timeout_list(ti)
    return LRU:get_score_range(0, ti)
end

function _M.get_count()
    return LRU:get_count()
end

return _M
