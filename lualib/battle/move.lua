local b_util = require "battle.util"
local stat_push = require"battle.stat".push
local hexagon = require "battle.hexagon"
local near_center = hexagon.near_center
local same_location = hexagon.same_location
local check_neibo = hexagon.check_neibo
local move_hex = require "battle.move_hex"
local move_hex_cant_arrive = move_hex.cant_arrive
local move_hex_add = move_hex.add
local move_hex_is_surrounded = move_hex.is_surrounded
local move_hex_mark_surround = move_hex.mark_surround
local move_hex_remove = move_hex.remove
local status_check = require"battle.status".check
local vector2 = require "battle.vector2"
local vector2_distance = vector2.distance
local vector2_movetowards = vector2.movetowards
local tremove = table.remove
local insert = table.insert

local object = require "battle.object"

local status_type = require "battle.status_type"
local status_type_rand_move<const> = status_type.rand_move
local status_type_no_move<const> = status_type.no_move

local ulog = b_util.log
local function log(bctx, self, ...)
    -- ulog(bctx, ...)
end

local function dump(...)
    -- ldump(...)
end

local _M = {}

local function check_moveto_center(self)
    if not near_center(self) then return self.hex end
end

local function stop_move(bctx, self, flag)
    if not near_center(self) then
        self.need_move = 1
    elseif move_hex_cant_arrive(bctx, self.hex, self) then
        self.need_move = 2
    end
    move_hex_add(bctx, self.hex, self)
    if not self.move_ctx then return end
    local move_ctx = self.move_ctx
    self.move_ctx = nil
    stat_push(bctx, self, "stop_move",
        {id = self.id, x = self.x, y = self.y, ti = bctx.btime.now})
    self:on_stopmove(bctx, move_ctx.rand_cfg)
    --[[
    log(bctx, self, "stop_move %s(%f,%f) (%d,%d) %s need_move:%s", self.id,
         self.x, self.y, self.hex.hx, self.hex.hy, flag,
        tostring(self.need_move))
    -- ]]
    return true
end

local function findpath(bctx, self, target, distance)
    if vector2_distance(self.hex, target) <= distance then -- 检测当前所在的格子中间是否为终点
        if not move_hex_cant_arrive(bctx, self.hex, self) then
            return self.hex
        end
    end
    if move_hex_is_surrounded(bctx, target.hex) then return end -- 检测目标是否被包围
    local objmgr = bctx.objmgr
    local pathhex
    local dest = objmgr.find_dest_line(self, target.hex, distance)
    --[[
    dump(dest,
        string.format("%s find_dest_line (%d,%d)->(%d,%d) distance:%f", self.id,
            self.hex.hx, self.hex.hy, target.hex.hx, target.hex.hy, distance))
    -- ]]
    if not dest or same_location(self.hex, dest) then
        pathhex = objmgr.findpath(self, target)
        if not next(pathhex) then -- 标记目标位置被包围
            move_hex_mark_surround(bctx, target.hex)
        end
        --[[
        dump(pathhex,
            string.format("%s findpath (%d,%d)->(%d,%d)", self.id, self.hex.hx,
                self.hex.hy, target.hex.hx, target.hex.hy))
        -- ]]
        local t_hex = target.hex
        while next(pathhex) do
            local p = pathhex[1]
            local d = vector2_distance(p, t_hex)
            if d > distance then break end
            dest = p
            tremove(pathhex, 1)
        end
        if not next(pathhex) then pathhex = nil end
    end
    -- 没有可行走的格子
    if not dest or same_location(self.hex, dest) then
        if move_hex_cant_arrive(bctx, self.hex, self) then -- 当前位置已有英雄，向旁边移动
            dest = objmgr.find_usable_hex(self.hex)
            --[[
            log(bctx, self, "%s(%d,%d) find usable hex to move (%d,%d)",
                self.id, self.hex.hx, self.hex.hy, dest and dest.hx or 0,
                dest and dest.hy or 0)
            -- ]]
        end
    end
    local path
    -- 阻挡检测
    if dest then
        local stop_dest = objmgr.check_line(self, dest)
        if stop_dest then
            if vector2_distance(self, stop_dest) > 2 then
                dest = stop_dest
                -- log(bctx, self, "check_line stop")
            elseif pathhex then -- 与阻挡点距离小于一个格子，按路径移动
                insert(pathhex, 1, dest)
                dest = tremove(pathhex)
                path = pathhex
                --[[
                log(bctx, self, "%s(%d,%d) findpath pathhex (%d,%d)",
                    self.id, self.hex.hx, self.hex.hy, dest and dest.hx or 0,
                    dest and dest.hy or 0)
                -- ]]
            else
                dest = nil
            end
        end
    end
    -- 双方相距最后一个格子时，调整终点
    if dest then
        local tctx = target.move_ctx
        if tctx then
            -- 寻路目的地和target的目的地是同一个格子的话，停在当前格子等待
            local t_dest = tctx.dest
            local t_hex = target.hex
            local s_hex = self.hex
            if same_location(dest, t_dest) and check_neibo(t_hex, dest) then -- 排除近战等远程的情况
                dest = check_moveto_center(self)
                -- log(bctx, self, "moveto center :near")
            elseif check_neibo(dest, s_hex, t_hex) and -- 双方在对角线上相邻,会出现侧身走位
                check_neibo(t_dest, s_hex, t_hex) then
                dest = check_moveto_center(self)
                -- log(bctx, self, "moveto center: far")
            end
        end
    end
    --[[
    if dest then
        log(bctx, self, "%s(%f,%f - %d,%d) findpath (%f,%f - %d,%d)", self.id,
            self.x, self.y, self.hex.hx, self.hex.hy, dest.x, dest.y, dest.hx,
            dest.hy)
    else
        log(bctx, self, "%s findpath no dest", self.id)
    end
    -- ]]
    return dest, path
end

local function check_target_move_away(ctx)
    local target = ctx.target
    if same_location(target.hex, ctx.target_hex) then return false end
    ctx.target_hex = target.hex
    return true
end

local function path_check(bctx, self, arrived)
    local ctx = self.move_ctx
    local pathhex = ctx.pathhex
    local final_dest = pathhex[1]
    local find
    if check_target_move_away(ctx) then
        find = true
    elseif move_hex_cant_arrive(bctx, final_dest, self) then
        find = true
    end
    local dest = ctx.dest
    if find then
        dest, pathhex = findpath(bctx, self, ctx.target, ctx.distance)
    end
    local changed
    if same_location(dest, ctx.dest) then
        if arrived then
            if pathhex then
                dest = tremove(pathhex)
                if not next(pathhex) then pathhex = nil end
                changed = true
            else
                dest = nil
            end
        end
    end
    ctx.pathhex = pathhex
    return dest, changed
end

local function dest_check(bctx, self, arrived)
    local ctx = self.move_ctx
    local dest = ctx.dest
    local find
    if check_target_move_away(ctx) then
        -- log(bctx, self, "%s target move away", self.id)
        find = true
    elseif move_hex_cant_arrive(bctx, dest, self) then
        --[[
        log(bctx, self, "%s dest_check cant_arrive(%d,%d)", self.id, dest.hx,
            dest.hy)
        -- ]]
        find = true
    end
    if find then
        dest, ctx.pathhex = findpath(bctx, self, ctx.target, ctx.distance)
    end
    if same_location(dest, ctx.dest) then
        if arrived then dest = nil end
    else
        return dest, true
    end
    return dest
end

local function move_check(bctx, self, arrived, stop)
    local ctx = self.move_ctx
    if status_check(self, status_type_rand_move) then
        if arrived then return end
        return ctx.dest
    end
    if ctx.pathhex then
        return path_check(bctx, self, arrived)
    else
        return dest_check(bctx, self, arrived)
    end
end

local function can_move(self)
    if self.attrs.speed <= 0 then return false end
    if object.is_dead(self) then return false end
    if status_check(self, status_type_no_move) then return false end
    return true
end
_M.can_move = can_move

local function move_calc(bctx, self, timestamp, stop)
    local ctx = self.move_ctx
    if not ctx then return end
    local t = timestamp - ctx.timestamp
    if t <= 0 then return end
    ctx.timestamp = timestamp
    local speed = self.attrs.speed -- 移动速度
    local pos, arrived = vector2_movetowards(self, ctx.dest, speed * t * 0.0001)

    bctx.objmgr.update(bctx, self, pos.x, pos.y)
    if stop then return end
    -- 先结算移动距离
    if not can_move(self) then return stop_move(bctx, self, "cant_move") end
    local dest, changed = move_check(bctx, self, arrived)
    if not dest then return stop_move(bctx, self, "no dest") end
    ctx.dest = dest
    if speed ~= ctx.speed then
        ctx.speed = speed
        changed = true
    end
    if changed or t >= 100 then
        stat_push(bctx, self, "start_move", {
            id = self.id,
            x = self.x,
            y = self.y,
            dx = dest.x,
            dy = dest.y,
            ti = timestamp
        })
    end
    --[[
    log(bctx, self, "move_calc %s (%f,%f)->(%f,%f) (%d,%d)->(%d,%d) %d",
        self.id, self.x, self.y, dest.x, dest.y, self.hex.hx, self.hex.hy,
        dest.hx, dest.hy, timestamp)
    -- ]]
end

function _M.start_move(bctx, self, target, distance, dest, pathhex, rand_cfg)
    if not can_move(self) then return end
    assert(not self.move_ctx)
    if self.need_move then self.need_move = nil end
    if not dest then
        dest, pathhex = findpath(bctx, self, target, distance)
        if not dest then return end
    end
    local timestamp = bctx.btime.now
    local hex = target.hex
    local ctx = {
        target = target,
        target_hex = hex,
        distance = distance,
        timestamp = timestamp,
        dest = dest,
        speed = self.attrs.speed,
        pathhex = pathhex,
        rand_cfg = rand_cfg
    }
    self.move_ctx = ctx
    stat_push(bctx, self, "start_move", {
        id = self.id,
        x = self.x,
        y = self.y,
        dx = dest.x,
        dy = dest.y,
        ti = timestamp
    })
    --[[
    log(bctx, self, "start_move %s (%f,%f)->(%f,%f) (%d,%d)->(%d,%d) %d",
        self.id, self.x, self.y, dest.x, dest.y, self.hex.hx, self.hex.hy,
        dest.hx, dest.hy, timestamp)
    -- ]]
    move_hex_remove(bctx, self.hex, self)
    return true
end

function _M.stop_move(bctx, self)
    move_calc(bctx, self, bctx.btime.now, true)
    stop_move(bctx, self, "other")
end

function _M.calc_pos(bctx, self, timestamp)
    local ti = timestamp or bctx.btime.now
    move_calc(bctx, self, ti)
end

function _M.move_update(bctx, self, timestamp)
    local ti = timestamp or bctx.btime.now
    move_calc(bctx, self, ti)
end

function _M.need_move(self)
    return self.need_move
end

function _M.clear_randcfg(self)
    local move_ctx = self.move_ctx
    if move_ctx then move_ctx.rand_cfg = nil end
end

return _M
