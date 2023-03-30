--[[
    消耗buff次数
]] local buffsys = require "skillsys.buffsys"
local get_buff_by_cfgid = buffsys.get_buff_by_cfgid
local reduce_times = buffsys.reduce_times
local get_buff_by_uuid = buffsys.get_buff_by_uuid

return function(bctx, src, ctx, tobj, ecfg, e_args)
    local ids = ecfg.parm
    if ids and next(ids) then
        for _, buffid in ipairs(ids) do
            local buff = get_buff_by_cfgid(tobj, buffid)
            if buff then reduce_times(bctx, tobj, ctx, buff) end
        end
    else
        local buff_uuid = e_args.buff_uuid
        local buff = get_buff_by_uuid(tobj, buff_uuid)
        if buff then reduce_times(bctx, tobj, ctx, buff) end
    end
end

