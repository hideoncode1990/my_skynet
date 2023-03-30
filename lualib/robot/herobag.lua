local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local log = require "robot.log"
local event = require "robot.event"
local utable = require "util.table"
local net = require "robot.net"

local _H = require "handler.client"
local _M = {}

local insert = table.insert
local sub = utable.sub

require "util"

local CFG, BASIC
skynet.init(function()
    CFG, BASIC = cfgproxy("hero", "basic")
end)

local ALL, STAGE, CNT, TEAM<const> = {}, {}, 0, 3

local function stage_sort(a, b)
    return ALL[a].lvreal > ALL[b].lvreal

end

local function del_from_substage(_, uuid, stage)
    local substage = STAGE[stage]
    for k, v in ipairs(substage) do
        if v == uuid then
            table.remove(substage, k)
            if not next(substage) then STAGE[stage] = nil end
            break
        end
    end
end

local function add_into_substage(_, uuid, stage)
    local substage = sub(STAGE, stage)
    insert(substage, uuid)
    table.sort(substage, stage_sort)
end

function _H.hero_list_start()
    ALL, STAGE, CNT = {}, {}, 0
end

function _H.hero_list(self, msg)
    for _, v in ipairs(msg.list) do
        local uuid = v.uuid
        local id = v.id
        local cfg = CFG[id]
        v.stage = cfg.stage
        v.tab = cfg.tab
        v.cfg = cfg
        -- v.attrs = nil
        -- v.zdl = nil
        ALL[uuid] = v
        CNT = CNT + 1
        local substage = sub(STAGE, v.stage)
        insert(substage, uuid)
    end

    for _, list in pairs(STAGE) do table.sort(list, stage_sort) end

    log(self, {opt = "hero_list"})

end

function _H.hero_add(self, msg)
    -- pdump(msg, "hero_add")
    local list = msg.list
    local temp = {}
    for _, v in ipairs(list) do
        local uuid = v.uuid
        local id = v.id
        local cfg = CFG[id]
        local stage = cfg.stage
        v.stage = stage
        v.tab = cfg.tab
        v.cfg = cfg
        -- v.attrs = nil
        -- v.zdl = nil
        ALL[uuid] = v
        CNT = CNT + 1
        local substage = sub(STAGE, stage)
        temp[stage] = true
        insert(substage, uuid)
    end
    for stage in pairs(temp) do table.sort(STAGE[stage], stage_sort) end
    log(self, {opt = "hero_add"})
    event.occur("hero_add", self, list)
end

function _H.hero_del(self, msg)
    -- pdump(msg, "hero_del")
    for _, uuid in ipairs(msg.list) do
        local info = ALL[uuid]
        del_from_substage(_, uuid, info.stage)

        ALL[uuid] = nil
        CNT = CNT - 1
    end
    log(self, {opt = "hero_del"})
end

function _H.hero_reset(self, msg)
    -- pdump(msg, "hero_reset")
    local info = ALL[msg.uuid]
    info.lvreal = 1
    info.level = 1
    info.equips = {}
    local substage = sub(STAGE, info.stage)
    table.sort(substage, stage_sort)
end

function _H.hero_inherit(self, msg)
    -- pdump(msg, "hero_inherit")
    for _, v in ipairs(msg.list) do
        local uuid = v.uuid
        local info = ALL[uuid]
        del_from_substage(_, uuid, info.stage)

        local id = v.id
        local cfg = CFG[id]
        v.stage = cfg.stage
        v.tab = cfg.tab
        v.cfg = cfg
        ALL[uuid] = v

        add_into_substage(_, uuid, v.stage)
    end
    log(self, {opt = "hero_inherit"})
end

function _H.hero_attrs_change(_, msg)
    for _, v in ipairs(msg.list) do
        local info = ALL[v.uuid]
        info.zdl = v.zdl

        local attrs = v.attrs
        if attrs then
            local info_attrs = info.attrs
            for id, val in pairs(attrs) do info_attrs[id] = val end
        end
    end
end

function _H.hero_level_change(self, msg)
    local info = ALL[msg.uuid]
    local old = info.level
    info.level = msg.level
    local substage = sub(STAGE, info.stage)
    table.sort(substage, stage_sort)
    log(self, {
        opt = "hero_level_change",
        uuid = msg.uuid,
        level = msg.level,
        old_level = old
    })
end

function _M.query(_, uuid)
    return ALL[uuid]
end

function _M.query_cnt()
    return CNT
end

function _M.query_all()
    return ALL
end

local function ordered_stage()
    local stages = {}
    for stage in pairs(STAGE) do insert(stages, stage) end
    table.sort(stages, function(a, b)
        return a > b
    end)
    return stages
end

function _M.calc_stage_top5(_, need_full)
    local stages = ordered_stage()

    local top, topdict, sametab, left, finish = {}, {}, {}, {}, nil
    for _, stage in ipairs(stages) do
        local stagesub = STAGE[stage]
        for _, uuid in ipairs(stagesub) do
            local info = ALL[uuid]
            local tab = info.tab

            if not sametab[tab] then
                insert(top, uuid)
                sametab[tab] = true
                topdict[uuid] = true
                if #top >= BASIC.herobest_count then
                    finish = true
                    break
                end
            else
                insert(left, uuid)
            end
        end
        if finish then break end
    end
    -- 如果不够5个，但是需要填满时
    if need_full and not finish and next(left) then
        for i = 1, BASIC.herobest_count - #top do
            local uuid = left[i]
            if uuid then
                insert(top, uuid)
                topdict[uuid] = true
            else
                break
            end
        end
    end
    return top, topdict
end

function _M.try_stageup(self)
    while true do
        local list, marked = {}, {}
        local stages = ordered_stage()

        for _, stage in ipairs(stages) do
            local stagesub = STAGE[stage]
            for _, tar_uuid in ipairs(stagesub) do
                if not marked[tar_uuid] then
                    local tar_info = ALL[tar_uuid]
                    local cfg = tar_info.cfg
                    local cost1, cost2 = cfg.cost1, cfg.cost2

                    marked[tar_uuid] = true

                    if cost1 then
                        local need_id, need_cnt = cost1[1], cost1[2]
                        local uuids, temp, cnt = {}, {[tar_uuid] = true}, 0
                        for uuid, info in pairs(ALL) do
                            if not marked[uuid] and info.id == need_id then
                                marked[uuid] = true
                                temp[uuid] = true
                                insert(uuids, uuid)
                                cnt = cnt + 1
                                if cnt >= need_cnt then
                                    break
                                end
                            end
                        end

                        local nm<const> = "cost1"
                        if cnt >= need_cnt then
                            insert(list, {
                                uuid = tar_uuid,
                                costs = {[nm] = {uuids = uuids, type = nm}}
                            })

                        else
                            for uuid in pairs(temp) do
                                marked[uuid] = nil
                            end
                        end
                    elseif cost2 then
                        local need_feature, need_stage, need_cnt = cost2[1],
                            cost2[2], cost2[3]
                        local uuids, temp, cnt = {}, {[tar_uuid] = true}, 0
                        for uuid, info in pairs(ALL) do
                            if not marked[uuid] and info.cfg.feature ==
                                need_feature and info.stage == need_stage then
                                marked[uuid] = true
                                temp[uuid] = true
                                insert(uuids, uuid)
                                cnt = cnt + 1
                                if cnt >= need_cnt then
                                    break
                                end
                            end
                        end

                        local nm<const> = "cost2"
                        if cnt >= need_cnt then
                            insert(list, {
                                uuid = tar_uuid,
                                costs = {[nm] = {uuids = uuids, type = nm}}
                            })
                        else
                            for uuid in pairs(temp) do
                                marked[uuid] = nil
                            end
                        end
                    end
                end
            end
        end
        if next(list) then
            local ret = net.request(self, 100, "hero_stageup_onekey",
                {list = list})
            local e = ret and ret.e
            log(self, {opt = "hero_stageup_onekey", e = e, result = e or false})
            if e ~= 0 then break end
        else
            break
        end
    end
end

function _M.generate_arena_lineup(self)
    local sametab = {}
    local stages = ordered_stage()

    local lineup, order = {}, 0
    local battlemax = BASIC.battlemax
    for _, stage in ipairs(stages) do
        local stagesub = STAGE[stage]
        for _, uuid in ipairs(stagesub) do
            local info = ALL[uuid]
            local tab = info.tab
            if not sametab[tab] then
                sametab[tab] = true

                local team = order % TEAM
                local pos = (order - team) // TEAM

                team = team + 1
                pos = pos + 1

                if pos > battlemax then
                    return lineup
                else
                    local linesub = lineup[team]
                    if not linesub then
                        linesub = {team = team, list = {}}
                        lineup[team] = linesub
                    end
                    table.insert(linesub.list, {pos = pos, uuid = uuid})
                end
                order = order + 1
            end
        end
    end
    if #lineup < TEAM then return end
    return lineup
end

function _M.generate_solo_lineup(self)
    local sametab = {}
    local stages = ordered_stage()

    local lineup, pos = {}, 0
    local battlemax = BASIC.battlemax

    for _, stage in ipairs(stages) do
        local stagesub = STAGE[stage]
        for _, uuid in ipairs(stagesub) do
            local info = ALL[uuid]
            local tab = info.tab
            if not sametab[tab] then
                pos = pos + 1
                table.insert(lineup, {uuid = uuid, pos = pos, tab = info.tab})
                sametab[tab] = true
                if pos >= battlemax then return lineup end
            end
        end
    end
    return lineup
end

return _M
