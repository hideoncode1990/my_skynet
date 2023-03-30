--[[
    击退/击飞
]] local vector2 = require "battle.vector2"
local object_move = require "battle.move"
local etype = require "skillsys.etype"
local status = require "battle.status"
local status_type = require "battle.status_type"
local status_type_no_beatback<const> = status_type.no_beatback
local etype_beatback<const> = etype.beat_back

local status_check = status.check
local calc_pos = object_move.calc_pos
local sub = vector2.sub
local eq_zero = vector2.eq_zero
local dir_rotate_scale = vector2.dir_rotate_scale
local add = vector2.add
local insert = table.insert
local floor = math.floor
local object = require "battle.object"
local stop_move = require"battle.move".stop_move

return function(bctx, src, ctx, tobj, ecfg)
    if object.cant_controlled(tobj) or
        status_check(tobj, status_type_no_beatback) then return end
    local distance = ecfg.parm[1] / 100
    calc_pos(bctx, tobj)
    local dir = sub(tobj, src)
    if eq_zero(dir) then dir = {x = src.x, y = src.y} end
    dir = dir_rotate_scale(dir, 0, distance)
    local dist_pos = add(tobj, dir)
    local objmgr = bctx.objmgr
    local _, stop_pos = objmgr.check_line(tobj, dist_pos)
    if stop_pos then dist_pos = stop_pos end
    objmgr.setpos(bctx, tobj, dist_pos)
    stop_move(bctx, tobj)
    insert(ctx.out, {
        effectid = ecfg.id,
        etype = etype_beatback,
        skillid = ctx.skillid,
        caster = src.id,
        target = tobj.id,
        args2 = floor(dist_pos.x * 100),
        args3 = floor(dist_pos.y * 100)
    })
end
