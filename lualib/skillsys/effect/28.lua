--[[
    冲锋
]] local vector2 = require "battle.vector2"
local object_move = require "battle.move"
local etype = require "skillsys.etype"
local status = require "battle.status"
local status_type = require "battle.status_type"
local sub = vector2.sub
local eq_zero = vector2.eq_zero
local distance = vector2.distance
local dir_rotate_scale = vector2.dir_rotate_scale
local add = vector2.add
local calc_pos = object_move.calc_pos
local status_check = status.check
local max = math.max
local min = math.min
local floor = math.floor
local insert = table.insert
local stop_move = require"battle.move".stop_move

local etype_dash<const> = etype.dash
local status_type_no_move<const> = status_type.no_move

return function(bctx, src, ctx, tobj, ecfg)
    if status_check(src, status_type_no_move) then return end
    local parm = ecfg.parm
    local near = parm[1] / 100 -- 离目标的距离

    calc_pos(bctx, src)
    local dir = sub(tobj, src)
    if eq_zero(dir) then dir = {x = src.x, y = src.y} end
    local d = distance(src, tobj)
    d = max(0, d - near)
    local max_dis = parm[2] -- 最大冲锋距离
    if max_dis then d = min(d, max_dis / 100) end
    dir = dir_rotate_scale(dir, 0, d)
    local dist_pos = add(src, dir)
    local objmgr = bctx.objmgr
    local _, stop_pos = objmgr.check_line(src, dist_pos)
    if stop_pos then dist_pos = stop_pos end
    objmgr.setpos(bctx, src, dist_pos)
    stop_move(bctx, src)
    insert(ctx.out, {
        effectid = ecfg.id,
        etype = etype_dash,
        skillid = ctx.skillid,
        caster = src.id,
        target = src.id,
        args2 = floor(dist_pos.x * 100),
        args3 = floor(dist_pos.y * 100)
    })
end
