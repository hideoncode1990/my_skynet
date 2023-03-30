--[[
    指定类型buff的剩余效果立即生效
]] local buffsys = require "skillsys.buffsys"
local run_at_once = buffsys.run_at_once

return function(bctx, src, ctx, tobj, ecfg)
    local ids = ecfg.parm
    for _, group in ipairs(ids) do run_at_once(bctx, tobj, group, ctx) end
end

