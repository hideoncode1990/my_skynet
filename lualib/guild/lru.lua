local utime = require "util.time"
local skiplist = require "skiplist.c"

local LRU = skiplist()

local _M = {}

local TOUCH = {}

function _M.mark(id)
    local now = utime.time_int()
    local touch = TOUCH[id]
    if touch then
        if now - touch > 1 then
            LRU:delete(touch, id)
            TOUCH[id] = nil
            touch = nil
        end
    end
    if not touch then
        LRU:insert(now, id)
        TOUCH[id] = now
    end
end

function _M.del(id, why)
    local touch = assert(TOUCH[id])
    TOUCH[id] = nil
    LRU:delete(touch, id)
end

function _M.get_head()
    local id = LRU:get_rank_range(1, 1)[1]
    return id, TOUCH[id]
end

function _M.clean()
    return LRU:delete_by_rank(0, LRU:get_count() - 1, function(id)
        _M.del(id, "clean")
    end)
end

function _M.timeout_list(ti)
    return LRU:get_score_range(0, ti)
end

function _M.get_count()
    return LRU:get_count()
end

return _M
