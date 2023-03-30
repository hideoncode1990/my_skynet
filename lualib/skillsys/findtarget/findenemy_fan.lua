--[[
扇形寻敌,以自己与目标为中轴，半径5，中轴线各30度，选择距离最近的2个目标
]] local vector2 = require "battle.vector2"
local vector2_sub = vector2.sub
local vector2_eq_zero = vector2.eq_zero
local vector2_opposite = vector2.opposite
local vector2_add = vector2.add
local vector2_dir_rotate_scale = vector2.dir_rotate_scale
local object_find = require "battle.object_find"
local find_target_poly = object_find.find_target_poly
local check = object_find.checkenemy
local stat_push = require"battle.stat".push

return function(bctx, ecfg, src, tobj, x, y, cdir)
    local args = ecfg.findtargetargs
    local dist, radius, short, long, max = args[1], args[2], args[3], args[4],
        args[5]

    if not tobj then tobj = {x = x, y = y} end
    local dir
    dir = vector2_sub(tobj, src)
    if vector2_eq_zero(dir) then
        dir.x = cdir and cdir.x or 1
        dir.y = cdir and cdir.y or 1
    end

    local rdir = vector2_opposite(dir)

    local local_mid = vector2_add(src, vector2_dir_rotate_scale(rdir, 0, dist))
    local remote_mid
    if radius < 0 then
        remote_mid = tobj
    else
        remote_mid = vector2_add(local_mid,
            vector2_dir_rotate_scale(dir, 0, radius))
    end

    local local_radius = vector2_dir_rotate_scale(dir, 90, short)
    local remote_radius = vector2_dir_rotate_scale(dir, 90, long)

    local v1 = vector2_add(local_mid, local_radius)
    local v2 = vector2_add(remote_mid, remote_radius)
    local v3 = vector2_sub(remote_mid, remote_radius)
    local v4 = vector2_sub(local_mid, local_radius)

    local vertexs = {v1, v2, v3, v4}
    local ret, ceils = find_target_poly(bctx, src, vertexs, max, check, tobj,
        ecfg)
    -- stat_push(bctx, src, "findtarget_poly", {points = vertexs, ceils = ceils})
    return ret
end
