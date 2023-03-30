--[[
    根据英雄数量增加属性
]] local enemy_hero_cnt = require"battle.global".enemy_hero_cnt
local buffsys_add = require"skillsys.buffsys".add

return function(bctx, src, ctx, tobj, ecfg)
    local cnt = enemy_hero_cnt(bctx, src)
    local buffid = ecfg.parm[1]
    buffsys_add(bctx, tobj, ctx, buffid, src, {attr_multi = cnt})
end

