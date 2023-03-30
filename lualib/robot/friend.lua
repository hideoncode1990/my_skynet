local fnopen = require "robot.fnopen"
local utable = require "util.table"
local _H = require "handler.client"
local logerr = require "log.err"

local _M = {}

local C
local NM<const> = "friend"

require "util"

local FCNT = 0

-- 设计friendlist 和applylist 的rid 互不重复
-- 用check 来检测rid是否重复
-- 如果重复，那么服务器的订阅也会出问题

local check
function _H.friend_info(self, msg)
    C = msg
    check = {}
    for rid in pairs(utable.sub(C, "friendlist")) do
        assert(not check[rid])
        FCNT = FCNT + 1
        check[rid] = true
    end

    for rid in pairs(utable.sub(C, "applylist")) do
        assert(not check[rid])
        check[rid] = true
    end
end

function _H.friend_add(self, msg)
    local friendlist = utable.sub(C, "friendlist")
    for rid, info in pairs(msg.list) do
        assert(not friendlist[rid], self.rname .. self.rid)
        assert(not check[rid], self.rname .. self.rid)
        friendlist[rid] = info
        check[rid] = true
        FCNT = FCNT + 1
    end
end

function _H.friend_del(self, msg)
    local friendlist = utable.sub(C, "friendlist")
    for _, rid in ipairs(msg.rids) do
        assert(friendlist[rid], self.rname .. self.rid)
        assert(check[rid], self.rname .. self.rid)
        friendlist[rid] = nil
        check[rid] = nil
        FCNT = FCNT - 1
    end
end

function _H.friend_applylist(self, msg)
    local old = C.applylist or {}
    for rid in pairs(msg.list) do
        if old[rid] then
            old[rid] = nil
        else
            assert(not check[rid], self.rname .. self.rid)
            check[rid] = true
        end
    end

    for rid in pairs(old or {}) do
        assert(check[rid], self.rname .. self.rid)
        check[rid] = nil
    end
    C.applylist = msg.list
end

function _H.friend_support_arrive(self, msg)
    local rid = msg.rid
    local friendlist = utable.sub(C, "friendlist")
    local info = friendlist[rid]

    info.accept = msg.accept
    info.send = msg.send
end

function _H.friend_support_onekey(self, msg)
    C.accept_point = msg.accept_point
    C.send_cnt = msg.send_cnt
    local friendlist = utable.sub(C, "friendlist")
    for rid, support_info in pairs(msg.change) do
        local info = friendlist[rid]

        info.send = support_info.send
        info.accept = support_info.accept
    end
end

function _H.friend_info_change(self, msg)
    local rid = msg.rid
    local friendlist = utable.sub(C, "friendlist")
    local applylist = utable.sub(C, "applylist")
    local info = friendlist[rid] or applylist[rid]
    for k, v in pairs(msg) do info[k] = v end
end

function _M.get(_, k)
    return k and C[k] or C
end

function _M.get_FCNT(_)
    return FCNT
end
return _M
