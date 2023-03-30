local skynet = require "skynet"
local net = require "robot.net"
local log = require "robot.log"
local _H = require "handler.client"

local my_channel, chnmax
local function get_self(self)
    return string.format(":%s_%d_%s", self.rname, self.rid, my_channel)
end

function _H.chat_native_info(self, msg)
    -- pdump(msg, "chat_native_info" .. get_self(self))
end

function _H.chat_world_info(self, msg)
    msg.contents = nil
    -- pdump(msg, "chat_world_info" .. get_self(self))
    my_channel = msg.channel
    chnmax = msg.chnmax
end

function _H.chat_push(self, msg)
    -- pdump(msg, "chat_push" .. get_self(self))
end

function _H.chat_chnmax_change(self, msg)
    -- pdump(msg, "chat_chnmax_change" .. get_self(self))
    chnmax = msg.chnmax
end

local ttype = {
    personal = 1, -- 个人
    native = 2, -- 本地
    world = 3, -- 世界
    guild = 4, -- 公会
    army = 5 -- 军团
}

local RAND = {
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o',
    'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', 'A', 'B', 'C', 'D',
    'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S',
    'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '1', '2', '3', '4', '5', '6', '7', '8',
    '9', '0'
}

local function content(self)
    local con = {"contnent_"}
    for _ = 1, 5 do table.insert(con, RAND[math.random(1, #RAND)]) end
    return table.concat(con) .. "----" .. get_self(self)
end

local function chat_native(self)
    local ret = assert(net.request(self, nil, "chat_chating", {
        content = content(self),
        type = ttype.native
    }))

    return ret
end

local function chat_channel_change(self, tar_channel)
    local ret = assert(net.request(self, nil, "chat_channel_change",
        {channel = tar_channel}))
    local e = ret and ret.e

    -- log(self,
    --     {opt = "chat_channel_change", e = e or false, channel = ret.channel})
    if e == 0 then
        my_channel = ret.channel
        return true
    end
    return false
end

local function chat_world(self)
    local ret = assert(net.request(self, nil, "chat_chating", {
        content = content(self),
        type = ttype.world
    }))
    local e = ret and ret.e
    -- log(self, {opt = "chat_world:  channel is " .. my_channel, e = e or false})
    return e == 0
end

return {
    onlogin = function(self)
        skynet.sleep(100)
        if my_channel then
            if not chat_world(self) then return false end
            skynet.sleep(100)

            if my_channel ~= 1 then
                if not chat_channel_change(self, 1) then
                    return false
                end
                if not chat_world(self) then return false end
            end
        else
            print("no_my_channel")
        end
    end
}
