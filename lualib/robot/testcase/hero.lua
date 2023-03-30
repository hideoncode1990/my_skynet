local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local herobag = require "robot.herobag"
local fnopen = require "robot.fnopen"
local sync = require "robot.sync"
local net = require "robot.net"
local log = require "robot.log"
local logerr = require "log.err"
local utable = require "util.table"
local herobest = require "robot.herobest"

require "robot.bag"
require "robot.eqbag"
require "robot.testcase.mainline"

require "util"
local insert = table.insert

local BASIC
skynet.init(function()
    BASIC = cfgproxy("basic")
end)

local function check_need_resolve(_, ALL, CNT) -- 当总数大于5时，回收绿卡
    local more = CNT - BASIC.herobest_count
    if more <= 0 then return end

    local temp = more
    local uuids = {}
    for uuid, info in pairs(ALL) do
        if info.stage <= 1 then -- 阶级为1的 为绿卡 不能一直升阶，回收
            insert(uuids, uuid)
            more = more - 1
            if more <= 0 then break end
        end
    end
    if temp ~= more then return uuids end
end

local function try_resolve(self, ALL, CNT)
    if not fnopen.check(self, "recycle") then return end
    local uuids = check_need_resolve(self, ALL, CNT)
    if uuids then
        local ret = net.request(self, 100, "hero_resolve", {uuids = uuids})
        local e = ret and ret.e
        if not ret or ret.e ~= 0 then
            log(self, {opt = "hero_resolve", e = e or false})
        end
        skynet.sleep(300)
    end
end

local function try_sync(self, ALL, SYNC, top, topdict)
    if not fnopen.check(self, "sync_level") then return end

    -- 尝试去买参数同步格子
    sync.try_buy(self)

    -- 若参数同步建筑开启了，为了升级，top5中没有加入建筑的试图加入建筑
    if SYNC.build then
        local sync_left = SYNC.left
        while next(sync_left) do
            local pos = next(sync_left)
            local find
            for _, uuid in ipairs(top) do
                if not SYNC.dict[uuid] then
                    find = uuid
                    break
                end
            end
            if not find then break end
            if not sync.add(self, find, pos) then break end

            skynet.sleep(30)
        end
    else
        -- 没建筑时，如果top5在参数同步的槽里，为了升级，得先取下，然后把槽的cd清除，
        for pos, info in pairs(SYNC.list) do
            local uuid = info.uuid
            if topdict[uuid] then
                local ret = net.request(self, 100, "herosync_remove",
                    {uuid = uuid, pos = pos})
                local e = ret and ret.e
                log(self, {opt = "herosync_remove", e = e or false})
                if e == 0 then
                    skynet.sleep(30)
                    ret =
                        net.request(self, 100, "herosync_cleancd", {pos = pos})
                    e = ret and ret.e

                    log(self, {opt = "herosync_cleancd", e = e or false})
                end
            end
        end
    end

    local _, herobest_dict = herobest.query()

    -- ALL中的某些英雄尝试加入参数同步
    while next(SYNC.left) do
        local pos = next(SYNC.left)
        local find
        for uuid in pairs(ALL) do
            if not topdict[uuid] and not herobest_dict[uuid] and
                not SYNC.dict[uuid] then
                find = uuid
                break
            end
        end

        if not find then break end
        if not sync.add(self, find, pos) then break end

        skynet.sleep(30)
    end
end

local function try_levelup(self, ALL, SYNC, top, topdict)
    if SYNC.build then -- 参数同步已经开启了建筑物
        return sync.try_build(self)
    else
        local copy = utable.copy(topdict)
        -- 试图升级top5
        while next(copy) do
            for _, uuid in ipairs(top) do
                if copy[uuid] then
                    local info = ALL[uuid]
                    local tar_lv = info.lvreal + 1
                    local ret = net.request(self, 100, "hero_levelup",
                        {uuid = uuid, tar_lv = tar_lv})

                    local e = ret and ret.e
                    log(self, {
                        opt = "hero_levelup",
                        uuid = uuid,
                        e = e or false,
                        tar_lv = tar_lv
                    })

                    if e == 0 then
                        -- 成功后可能刚好建筑物开启
                        info.lvreal = ret.lvreal
                        if SYNC.build then
                            return sync.try_build(self)
                        end
                    else
                        copy[uuid] = nil
                    end
                end
            end
        end
    end
end

local function main_try(self)
    local ALL, CNT, SYNC = herobag.query_all(), herobag.query_cnt(),
        sync.get_cache()

    -- 首先把品质最低的回收
    try_resolve(self, ALL, CNT)

    -- 尝试升阶
    herobag.try_stageup(self)

    -- 找出品质最高的，等级从高到低的，尽量tab不相同的top5
    local top, topdict = herobag.calc_stage_top5(self, true)

    -- 尝试打开参数同步槽位
    try_sync(self, ALL, SYNC, top, topdict)

    -- 最终，尝试升级
    try_levelup(self, ALL, SYNC, top, topdict)

end

return {onlogin = main_try}
