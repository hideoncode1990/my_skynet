local skynet = require "skynet"
local fnopen = require "robot.fnopen"
local friend = require "robot.friend"
local net = require "robot.net"
local cfgproxy = require "cfg.proxy"

local NM<const> = "friend"

local BASIC, NAMEMGR
skynet.init(function()
    BASIC = cfgproxy("basic")
    NAMEMGR = skynet.uniqueservice("robot/rname")
end)

require "util"

local function friend_apply_agree_onekey(self)
    local ret = net.request(self, 100, "friend_apply_res", {agree = 1})
    -- print("friend_apply_agree_onekey", self.rname, ret.e)
end

local function friend_apply_refuse_onekey(self)
    local ret = net.request(self, 100, "friend_apply_res", {})
    -- print("friend_apply_refuse_onekey", self.rname, ret.e)
end

local function friend_support_onekey(self)
    local ret = net.request(self, 100, "friend_support_onekey", {})
    -- print("friend_support_onekey", self.rname, ret.e)
end

local function friend_delete(self, dels)
    local ret = net.request(self, 100, "friend_delete", {rids = dels})
    -- print("friend_delete", self.rname, ret.e)
end

local function friend_query(self, rname)
    local ret = net.request(self, 100, "friend_query", {rname = rname})
    -- print("friend_query", self.rname, ret.e)
    return ret
end

local function friend_apply(self, rid)
    local ret = net.request(self, 100, "friend_apply", {rid = rid})
    -- print("friend_apply", self.rname, ret.e)
    return ret
end

local function friend_try(self)
    -- 先同意申请表里面的申请
    local applist = friend.get(self, "applylist")
    if next(applist) then
        friend_apply_agree_onekey(self)
        skynet.sleep(30)
    end
    -- 申请表里面的剩下的就拒绝
    if next(applist) then
        friend_apply_refuse_onekey(self)
        skynet.sleep(30)
    end
    -- 一键发送和接受友情点
    friend_support_onekey(self)
    skynet.sleep(30)
    -- 如果好友满了 全删
    if friend.get_FCNT(self) >= BASIC.friend_limit then
        local dels = {}
        local friendlist = friend.get(self, "friendlist")
        for rid in pairs(friendlist) do
            -- if math.random(1, BASIC.friend_limit) <= 10 then
            table.insert(dels, rid)
            -- end
        end
        if #dels > 0 then
            friend_delete(self, dels)
            skynet.sleep(30)
        end
    end

    -- 通过名字查询， 试图去加好友
    local try_name = skynet.call(NAMEMGR, "lua", "rand")

    local ret = friend_query(self, try_name)
    if ret.e == 0 then
        local list = ret.list
        for _, v in ipairs(list) do
            if v.rname == try_name then
                friend_apply(self, v.rid)
                return true
            end
        end
    end
end

return {
    onlogin = function(self)
        skynet.call(NAMEMGR, "lua", "reg", self.rname)
        if fnopen.check(self, NM) then friend_try(self) end
    end
}
