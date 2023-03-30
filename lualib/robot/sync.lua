local skynet = require "skynet"
local log = require "robot.log"
local net = require "robot.net"
local fnopen = require "robot.fnopen"

local _H = require "handler.client"
local _M = {}

local SYNC

--  {
--     list = CACHE.pos2d,
--     size = tablemax(self),
--     buy = C.buy,
--     build = C.build
-- }

function _H.herosync_list(self, msg)
    SYNC = msg
    msg.opt = "herosync_list"
    log(self, msg)
    local dict, left = {}, {}
    for i = 1, SYNC.size do left[i] = true end
    for pos, info in pairs(SYNC.list) do
        if info.uuid then
            dict[info.uuid] = pos
            left[pos] = nil
        end
    end
    SYNC.dict = dict
    SYNC.left = left
end

function _M.try_build(self) -- 尝试给参数同步的建筑物升级
    if not fnopen.check(self, "sync_level") then return end
    if not SYNC.build then return end

    while true do
        local tar_lv = SYNC.build + 1
        local ret = net.request(self, 100, "herosync_build_levelup",
            {level = tar_lv})
        local e = ret and ret.e

        log(self, {
            opt = "herosync_build_levelup",
            e = e or false,
            build_level = e == 0 and tar_lv
        })
        if e == 0 then
            SYNC.build = tar_lv
            skynet.sleep(30)
        else
            return
        end
    end
end

function _M.try_buy(self)
    if not fnopen.check(self, "sync_level") then return end

    while true do
        local size = SYNC.size
        local pos = size + 1
        local ret = net.request(self, 100, "herosync_buy", {pos = pos})
        local e = ret and ret.e
        log(self, {opt = "herosync_buy", e = e or false, pos = pos})
        if e == 0 then
            SYNC.buy = (SYNC.buy or 0) + 1
            skynet.sleep(30)
        else
            return
        end
    end
end

function _M.add(self, uuid, pos)
    local ret = net.request(self, 100, "herosync_add", {pos = pos, uuid = uuid})
    local e = ret and ret.e
    if e == 0 then
        SYNC.list[pos] = {pos = pos, uuid = uuid}
        SYNC.dict[uuid] = pos
        SYNC.left[pos] = nil
        return true
    end
end

function _M.get_cache(self)
    return SYNC
end

return _M
