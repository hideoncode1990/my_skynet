local skynet = require "skynet"
local cfgdata = require "cfg.data"
local skillsys = require "skillsys.skill_sys"
local status = require "battle.status"
local stat = require "battle.stat"
local uniq_id = require"uniq.c".id
local _BG = require "battle.global"
local passive_type = require "skillsys.passive_type"
local object = require "battle.object"

local mathmin = math.min
local tremove = table.remove
local tinsert = table.insert
local _M = {}

local unpack = table.unpack
local tsort = table.sort
local cast_effectlist = skillsys.cast_effectlist
local status_add_table = status.add_table
local status_del_table = status.del_table
local stat_push = stat.push

local passive_trigger = _BG.passive_trigger
local get_traits_cnt = _BG.get_traits_cnt

local passive_no_control<const> = passive_type.no_control
local passive_buff_over<const> = passive_type.buff_over
local passive_beadd_buff<const> = passive_type.beadd_buff

--[[
-- buffsys 数据结构
self.buffsys_data = {
    group_list = {"group1", "group2"}, --确保播放录像时遍历顺序一致
    ["group1"] = {
        [-1] = 0, -- 下次update最小时间
        [0] = 3, -- valid buff size
        [1] = {id = "buff1"},
        [2] = {id = "buff2", expired = true},
        [3] = {id = "buff3"},
        [4] = {id = "buff4"}
    },
    ["group2"] = {[0] = 1, [1] = {id = "buff100"}}
}
-- ]]

local ulog = require"battle.util".log
local function log(bctx, id, ...)
    -- ulog(bctx, ...)
end

-- local buff_type = {negative = 1, positive = 2}

local CFG
skynet.init(function()
    CFG = cfgdata.buff
end)

local function buff_next(buffs, n)
    n = (n or 0) + 1
    for i = n, #buffs do
        local buff = buffs[i]
        if not buff.expired then return i, buff end
    end
end

local function run_buff_effect(bctx, self, ctx, buff, effectlist)
    if not effectlist then return end
    if not ctx.skillid then ctx.skillid = 0 end
    cast_effectlist(bctx, buff.src, ctx, effectlist, self, self.x, self.y,
        {buff_uuid = buff.uuid, buff_ctx = buff.ctx})
end

local function can_add(bctx, self, cfg, src, ctx)
    if cfg.controltype then
        if object.cant_controlled(self) then -- 免控
            passive_trigger(bctx, passive_no_control, self, src, ctx)
            return false
        end
    end
    return true
end

local function del_buff(bctx, self, ctx, buff, buffs)
    if buff.expired then return end
    buff.expired = true
    buffs[0] = buffs[0] - 1
    local cfg = buff.cfg
    -- 永久buff需要确定下次更新时间
    if cfg.duration == 0 then
        local now = bctx.btime.now
        buffs[-1] = now
        self.buffsys_data.min_nextup = now
    end

    -- log(bctx, self.id, "%s del_buff %d", self.id, cfg.id)
    if not buff.delay then
        local bindstate = cfg.bindstate
        if bindstate then status_del_table(self, bindstate) end
        run_buff_effect(bctx, self, ctx, buff, cfg.endeffect)
        if cfg.passive_trigger then
            passive_trigger(bctx, passive_buff_over, self, buff.src, ctx,
                {buffid = cfg.id})
        end
    end
    if cfg.showtype then
        stat_push(bctx, self, "buff_del", {tid = self.id, uuid = buff.uuid})
    end
    return buff
end

local function calc_duration(bctx, owner, cfg)
    local duration = cfg.duration
    local atime = cfg.atime
    if atime then
        local tag_id, tag_v, base_v, max_n, num = unpack(atime)
        local cnt = get_traits_cnt(bctx, owner, tag_id, tag_v) - (num or 0)
        if cnt > 0 then
            cnt = mathmin(max_n, cnt)
            duration = duration + base_v * cnt
        end
    end
    return duration
end

local function new_buff(bctx, self, src, cfg, buff_ctx)
    local start_time = bctx.btime.now
    local duration = calc_duration(bctx, src, cfg)
    local delay = cfg.delay
    local buff = {
        uuid = uniq_id(),
        cfg = cfg,
        start_time = start_time,
        src = src,
        ctx = buff_ctx,
        last_ti = nil,
        duration = duration,
        delay = cfg.delay
    }
    buff.duration = duration
    local min_nextti
    if delay then
        min_nextti = start_time + delay
    else
        if cfg.updateeffect then min_nextti = start_time + cfg.interval end
        if duration > 0 then
            local endti = start_time + duration
            min_nextti = mathmin(endti, min_nextti or endti)
        end
    end
    return buff, min_nextti
end

local function refresh_duration(buffs, now)
    for i = 1, #buffs do
        local buff = buffs[i]
        if not buff.expired then buff.start_time = now end
    end
end

local function before_add(bctx, self, ctx, src, new_cfg, buff_ctx)
    local group = new_cfg.group
    local buffsys_data = self.buffsys_data
    local buffs = buffsys_data[group]
    if buffs then
        if #buffs >= 99 then
            local ids = {}
            for i = 1, #buffs do
                local buff = buffs[i]
                local id = buff.cfg.id
                table.insert(ids, id)
            end
            error(string.format("%s add buff group=%d too many=%s", self.id,
                group, table.concat(ids, ',')))
        end
        local add_max = new_cfg.add_max
        if not add_max then -- 不可叠加的，高等级覆盖低等级
            local _, o_buff = buff_next(buffs)
            if o_buff then
                local old_cfg = o_buff.cfg
                if old_cfg.level > new_cfg.level then
                    return false
                end
                if old_cfg.level == new_cfg.level and new_cfg.prolong then -- 延长时间
                    o_buff.duration = o_buff.duration +
                                          calc_duration(bctx, src, new_cfg)
                    return false
                end
            end
        end
        add_max = add_max or 1
        --[[
        if not buff_ctx and not new_cfg.refresh and add_max == 1 then
            skynet.error("traceback buff should set refresh", new_cfg.id)
        end
        -- ]]
        if new_cfg.refresh and buffs[0] >= add_max then -- 刷新所有同类型buff(超过最大叠加数量时)
            refresh_duration(buffs, bctx.btime.now)
            return false
        end
        local i, o_buff
        while buffs[0] >= add_max do
            i, o_buff = buff_next(buffs, i)
            del_buff(bctx, self, ctx, o_buff, buffs)
        end
    end
    return true
end

local function run_starteffect(bctx, self, ctx, cfg, buff)
    local bindstate = cfg.bindstate
    if bindstate then
        status_add_table(self, bindstate)
        local objtype = self.objtype
        self:on_addstatus(bctx, bindstate)
    end
    run_buff_effect(bctx, self, ctx, buff, cfg.starteffect)
end

local function add(bctx, self, ctx, src, cfg, buff, nextti)
    local group = cfg.group
    local buffsys_data = self.buffsys_data
    local buffs = buffsys_data[group]
    if not buffs then
        buffs = {[0] = 0} -- buffs[0] 有效buff数量
        buffsys_data[group] = buffs
        tinsert(buffsys_data.group_list, group)
    end
    tinsert(buffs, buff)
    buffs[0] = buffs[0] + 1
    if nextti then
        if not buffs[-1] or nextti < buffs[-1] then
            buffs[-1] = nextti
            local min_nextup = buffsys_data.min_nextup
            if not min_nextup or nextti < min_nextup then
                buffsys_data.min_nextup = nextti
            end
        end
    end

    if cfg.showtype then
        stat_push(bctx, self, "buff_add", {
            tid = self.id,
            uuid = buff.uuid,
            cfgid = cfg.id,
            fromid = src.id
        })
    end
    -- log(bctx, self.id, "%s add buff %d", self.id, cfg.id)
    if not buff.delay then run_starteffect(bctx, self, ctx, cfg, buff) end
    passive_trigger(bctx, passive_beadd_buff, self, src, ctx, {buffid = cfg.id})
    return buff
end

local function buffadd(bctx, self, ctx, cfgid, src, buff_ctx)
    local cfg = CFG[cfgid]
    if not cfg then error("not exist buff setting " .. tostring(cfgid)) end
    if not can_add(bctx, self, cfg, src, ctx) then return end
    if not before_add(bctx, self, ctx, src, cfg, buff_ctx) then return end
    local buff, nextti = new_buff(bctx, self, src, cfg, buff_ctx)
    return add(bctx, self, ctx, src, cfg, buff, nextti)
end
_M.add = buffadd

function _M.inherit(bctx, self, ctx, buff, src)
    local cfg = buff.cfg
    if not can_add(bctx, self, cfg, src, ctx) then return end
    if not before_add(bctx, self, ctx, src, cfg) then return end
    local n_buff, nextti = new_buff(bctx, self, buff.src, cfg, buff.ctx)
    return add(bctx, self, ctx, src, cfg, n_buff, nextti)
end

local function buffdel(bctx, self, uuid, ctx)
    local buffsys_data = self.buffsys_data
    local group_list = buffsys_data.group_list
    for j = 1, #group_list do
        local grp = group_list[j]
        local buffs = buffsys_data[grp]
        for i = 1, #buffs do
            local bf = buffs[i]
            if uuid == bf.uuid then
                if del_buff(bctx, self, ctx or {}, bf, buffs) then
                    return bf
                end
            end
        end
    end
end
_M.del = buffdel

function _M.del_by_cfgid(bctx, self, cfgid, max, ctx)
    local cfg = CFG[cfgid]
    local cnt = 0
    local buffs = self.buffsys_data[cfg.group]
    if buffs then
        for i = 1, #buffs do
            local buff = buffs[i]
            if cfgid == buff.cfg.id then
                if del_buff(bctx, self, ctx, buff, buffs) then
                    cnt = cnt + 1
                    if cnt >= max then break end
                end
            end
        end
    end
end

local function run_at_once(bctx, self, buff, ctx, buffs)
    local start_time = buff.start_time
    local last_ti = buff.last_ti or start_time
    local cfg = buff.cfg
    if buff.duration > 0 then
        local updateeffect, interval = cfg.updateeffect, cfg.interval
        if updateeffect then
            while last_ti < start_time + buff.duration do
                last_ti = last_ti + interval
                run_buff_effect(bctx, self, ctx, buff, updateeffect)
            end
            buff.last_ti = last_ti
        end
    end
    del_buff(bctx, self, ctx, buff, buffs)
end

function _M.run_at_once(bctx, self, _g, ctx)
    local buffs = self.buffsys_data[_g]
    if buffs then
        for i = 1, #buffs do
            local buff = buffs[i]
            if not buff.expired then
                run_at_once(bctx, self, buff, ctx, buffs)
            end
        end
    end
end

function _M.get_buff_cnt(self, cfgid)
    local cfg = CFG[cfgid]
    local buffs = self.buffsys_data[cfg.group]
    return buffs and buffs[0] or 0
end

function _M.check_exist_bygroup(self, _g)
    local buffsys_data = self.buffsys_data
    local buffs = buffsys_data[_g]
    if buffs and buffs[0] > 0 then return true end
    return false
end

function _M.del_by_type(bctx, self, _type, max, ctx)
    local cnt = 0
    local buffsys_data = self.buffsys_data
    local group_list = buffsys_data.group_list
    for j = 1, #group_list do
        local grp = group_list[j]
        local buffs = buffsys_data[grp]
        for i = 1, #buffs do
            local buff = buffs[i]
            if not buff.expired then
                if _type == buff.cfg.type then
                    del_buff(bctx, self, ctx, buff, buffs)
                    cnt = cnt + 1
                    if max and cnt >= max then return end
                end
            end
        end
    end
end

function _M.get_buff_by_type(self, _type)
    local buffsys_data = self.buffsys_data
    local group_list = buffsys_data.group_list
    for j = 1, #group_list do
        local grp = group_list[j]
        local buffs = buffsys_data[grp]
        for i = 1, #buffs do
            local buff = buffs[i]
            if not buff.expired then
                if _type == buff.cfg.type then return buff end
            end
        end
    end
end

function _M.get_buff_by_uuid(self, uuid)
    local buffsys_data = self.buffsys_data
    local group_list = buffsys_data.group_list
    for j = 1, #group_list do
        local grp = group_list[j]
        local buffs = buffsys_data[grp]
        for i = 1, #buffs do
            local buff = buffs[i]
            if not buff.expired then
                if uuid == buff.uuid then return buff end
            end
        end
    end
end

function _M.get_buff_by_cfgid(self, cfgid)
    local cfg = CFG[cfgid]
    local buffs = self.buffsys_data[cfg.group]
    if buffs then
        for i = 1, #buffs do
            local buff = buffs[i]
            if not buff.expired then
                if cfgid == buff.cfg.id then return buff end
            end
        end
    end
end

function _M.check_control_buff(self, ctype)
    local buffsys_data = self.buffsys_data
    local group_list = buffsys_data.group_list
    for j = 1, #group_list do
        local grp = group_list[j]
        local buffs = buffsys_data[grp]
        for i = 1, #buffs do
            local buff = buffs[i]
            if not buff.expired then
                local _type = buff.cfg.controltype
                if _type and _type == (ctype or _type) then
                    return buff
                end
            end
        end
    end
end

function _M.reduce_times(bctx, self, ctx, buff)
    local buff_ctx = buff.ctx
    local times = buff_ctx.times
    times = times - 1
    if times <= 0 then
        buffdel(bctx, self, buff.uuid, ctx)
        return
    end
    buff_ctx.times = times
end

function _M.update(bctx, self)
    local D = self.buffsys_data
    if not D then return end
    local now = bctx.btime.now
    local min_nextup = D.min_nextup
    if not min_nextup or now < min_nextup then return end
    min_nextup, D.min_nextup = nil, nil

    local ctx, dels = self.buffsys_ctx, self.buffsys_dels
    local group_list = D.group_list
    for i = 1, #group_list do
        local grp = group_list[i]
        local buffs = D[grp]
        local min_nextti
        min_nextti, buffs[-1] = buffs[-1], nil
        if min_nextti and now >= min_nextti then
            min_nextti = nil
            for ii = 1, #buffs do
                local buff = buffs[ii]
                if buff.expired then
                    if not dels[grp] then dels[grp] = i end
                else
                    local start_time = buff.start_time
                    local cfg = buff.cfg
                    if buff.delay then
                        start_time = start_time + buff.delay
                        if now >= start_time then
                            buff.delay = nil
                            buff.start_time = start_time
                            run_starteffect(bctx, self, ctx, cfg, buff)
                        else
                            min_nextti =
                                mathmin(start_time, min_nextti or start_time)
                        end
                    end
                    if not buff.delay then
                        local updateeffect = cfg.updateeffect
                        if updateeffect then
                            local next_ti =
                                (buff.last_ti or start_time) + cfg.interval
                            if now >= next_ti then
                                run_buff_effect(bctx, self, ctx, buff,
                                    updateeffect)
                                buff.last_ti = next_ti
                                next_ti = next_ti + cfg.interval
                            end
                            min_nextti = mathmin(next_ti, min_nextti or next_ti)
                        end
                        if buff.duration > 0 then
                            local endti = start_time + buff.duration
                            if now >= endti then
                                del_buff(bctx, self, ctx, buff, buffs)
                                if not dels[grp] then
                                    dels[grp] = i
                                end
                            else
                                min_nextti = mathmin(endti, min_nextti or endti)
                            end
                        end
                    end
                end
            end
        end
        if min_nextti then
            buffs[-1] = mathmin(min_nextti, buffs[-1] or min_nextti)
            min_nextup = mathmin(min_nextti, min_nextup or min_nextti)
        end
    end
    if min_nextup then
        D.min_nextup = mathmin(min_nextup, D.min_nextup or min_nextup)
    end
    if next(ctx) then self.buffsys_ctx = {} end

    if next(dels) then
        local mark
        for grp, pos in pairs(dels) do
            local buffs = D[grp]
            if buffs[0] > 0 then
                for i = #buffs, 1, -1 do
                    local buff = buffs[i]
                    if buff.expired then tremove(buffs, i) end
                end
            else
                D[grp] = nil
                group_list[pos] = -1
                mark = true
            end
        end
        if mark then
            for i = #group_list, 1, -1 do
                if group_list[i] == -1 then
                    table.remove(group_list, i)
                end
            end
        end
        self.buffsys_dels = {}
    end
end

function _M.get_nextbuff_ti(self)
    local D = self.buffsys_data
    if D then return D.min_nextup end
end

local function init_buffs(bctx, self)
    local ids = self.init_buffs
    if ids then
        local ctx = {}
        for _, cfgid in ipairs(ids) do
            buffadd(bctx, self, ctx, cfgid, self)
        end
    end
end

function _M.init(self, bctx)
    self.buffsys_ctx = {}
    self.buffsys_dels = {}
    self.buffsys_data = {group_list = {}}
    init_buffs(bctx, self)
end

function _M.destroy(self, bctx)
    local buffsys_data = self.buffsys_data
    local group_list = buffsys_data.group_list
    for j = 1, #group_list do
        local grp = group_list[j]
        local buffs = buffsys_data[grp]
        for i = 1, #buffs do
            local buff = buffs[i]
            if not buff.expired then
                del_buff(bctx, self, {}, buff, buffs)
            end
        end
    end
    self.buffsys_data = nil
    self.buffsys_ctx = nil
    self.buffsys_dels = nil
end

require "battle.mods"("buffsys", _M)

return _M
