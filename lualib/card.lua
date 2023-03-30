local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local utable = require "util.table"
local schema = require "mongo.schema"

local insert = table.insert
local min = math.min

local CFG
skynet.init(function()
    CFG = cfgproxy("treasure")
end)

local special = {
    quality_effect = 1, -- 每拥有一张大于等于指定品质的卡片，则产生一个被动效果，排除自己
    multi_effect = 2, -- 有此卡片后，每次使用某特殊道具，增加一个被动
    win_atk = 3, -- 每获胜一场战斗，获得一个被动(加攻击)
    battle_end_recover = 4, -- 战斗结束后，所有未阵亡英雄恢复已损失生命值的x
    spring_extra_recover = 5, -- 使用泉水时，额外恢复x的生命和能量
    mapid = 6, -- 在某个地图id中，获得额外被动
    revival = 7, -- 使用特殊道具，增加一个被动，最多增加X个
    win_def = 8 -- 每获胜一场战斗，获得一个被动(加防御)
}

local field = {
    victory = function(self, pc, nm, v, bc)
        local para = pc.get(self)
        local buffs = bc.get(self)
        for id in pairs(buffs) do
            local spc = CFG[id].special
            if spc == special.win_atk then
                local data = utable.sub(para, nm)
                data["win_atk"] = (data["win_atk"] or 0) + (v or 1)
                pc.dirty(self)
            elseif spc == special.win_def then
                local data = utable.sub(para, nm)
                data["win_def"] = (data["win_def"] or 0) + (v or 1)
                pc.dirty(self)
            end
        end
    end,

    revival = function(self, pc, nm, v, bc)
        local para = pc.get(self)
        local buffs = bc.get(self)
        for id in pairs(buffs) do
            if CFG[id].special == special.revival then
                para[nm] = (para[nm] or 0) + (v or 1)
                pc.dirty(self)
                return true
            end
        end
    end,

    mapid = function(self, pc, nm, v)
        local para = pc.get(self)
        para[nm] = v
        pc.dirty(self)
    end
}

local function calc_inner(buff)
    local cnts, quality, mark = utable.copy(buff), {}, {}
    for id, v in pairs(buff) do
        local cfg = CFG[id]
        local tp = cfg.type
        if tp then
            local ex_id = mark[tp]
            if ex_id then
                local ex_cfg = CFG[ex_id]
                if cfg.quality > ex_cfg.quality then
                    mark[tp] = id
                    cnts[ex_id] = nil
                else
                    cnts[id] = nil
                end
            else
                mark[tp] = id
            end
        end

        local cnt = cnts[id]
        if cfg.max and cnt then cnts[id] = min(cfg.max, cnt) end

        if cfg.special ~= special.quality_effect then
            for i = 1, cfg.quality do
                quality[i] = (quality[i] or 0) + v
            end

        end
    end
    return cnts, quality
end

return function(bc, pc)
    bc.schema(schema.SAR())
    local CACHE = {}

    local function query_cnts_quality(buff)
        local cnts, quality = CACHE.cnts, CACHE.quality
        if not cnts then
            cnts, quality = calc_inner(buff)
            CACHE.cnts, CACHE.quality = cnts, quality
        end
        return cnts, quality
    end

    local function add_effect(list, effect, cnt)
        if effect and cnt > 0 then
            for _ = 1, cnt do insert(list, effect) end
        end
    end

    local function passive_for_battle(buff, para, passive_list)
        local cnts, quality = query_cnts_quality(buff)
        for id, cnt in pairs(cnts) do
            local cfg = CFG[id]
            local cfgmax = cfg.max or math.maxinteger
            local count = min(cfgmax, cnt)
            local spc = cfg.special
            if spc == special.quality_effect then
                local num = quality[cfg.quality] or 0
                count = min(cfgmax, num)
            elseif spc == special.multi_effect then
                local i = 0
                while true do
                    i = i + 1
                    local n, effect = cfg.para[2 * i - 1], cfg.para[2 * i]
                    if not n then break end
                    if count >= n then
                        insert(passive_list, effect)
                    end
                end

            elseif spc == special.win_atk then
                count = min(cfgmax,
                    (utable.sub(para, "victory")["win_atk"] or 0))
            elseif spc == special.win_def then
                count = min(cfgmax,
                    (utable.sub(para, "victory")["win_def"] or 0))
            elseif spc == special.mapid then
                count = 0
                for _, mapid in ipairs(cfg.para) do
                    if para["mapid"] == mapid then
                        count = 1
                        break
                    end
                end

            elseif spc == special.revival then
                count = min(cfgmax, (para["revival"] or 0))
            end

            add_effect(passive_list, CFG[id].effect, count)
        end
        return passive_list
    end

    local function data_for_battle(buff)
        local cnts = query_cnts_quality(buff)

        local data = CACHE.data
        if not data then
            local ber, ser = 0, 0
            for id in pairs(cnts) do
                local cfg = CFG[id]
                if cfg.special == special.battle_end_recover then
                    ber = ber + cfg.para[1]
                elseif cfg.special == special.spring_extra_recover then
                    ser = ser + cfg.para[1]
                end
            end
            data = {
                battle_end_recover = ber / 1000,
                spring_extra_recover = ser / 1000
            }
            CACHE.data = data
        end
        return data
    end

    return {
        add = function(id, self)
            local C = bc.get(self)
            C[id] = (C[id] or 0) + 1
            bc.dirty(self)
            CACHE = {}
            return C[id]
        end,
        get = function(self)
            return bc.get(self)
        end,
        passive_list = function(passive_list, self)
            return passive_for_battle(bc.get(self), pc.get(self), passive_list)
        end,
        passive_table = function(k, self)
            local info = data_for_battle(bc.get(self))
            return k and info[k] or info
        end,
        trigger = function(k, v, self)
            field[k](self, pc, k, v, bc)
        end
    }
end
