--[[
    传染(将指定目标的buff传递给其他英雄)
]] local buffsys = require "skillsys.buffsys"
local get_buff_cnt = buffsys.get_buff_cnt
local buffsys_add = buffsys.add
local cast_effectlist = require"skillsys".cast_effectlist

return function(bctx, src, ctx, tobj, ecfg, e_args)
    local parm = ecfg.parm
    local _type, buffid = parm[1], parm[2]
    local max_n
    if _type == 1 then -- 主效果
        max_n = get_buff_cnt(tobj, buffid)
        cast_effectlist(bctx, src, ctx, ecfg.attach_effects, tobj, tobj.x,
            tobj.y, {max_n = max_n})
    elseif _type == 2 then -- 子效果
        local cnt = get_buff_cnt(tobj, buffid)
        for _ = cnt, e_args.max_n do
            buffsys_add(bctx, tobj, ctx, buffid, src)
        end
    end
end

