--[[
    转移buff(保留最初buff来源src)
]] local buffsys = require "skillsys.buffsys"
local get_buff_by_cfgid = buffsys.get_buff_by_cfgid
local buffsys_del = buffsys.del
local buffsys_inherit = buffsys.inherit

return function(bctx, src, ctx, tobj, ecfg)
    local ids = ecfg.parm
    for _, buffid in ipairs(ids) do
        local buff = get_buff_by_cfgid(src, buffid)
        if buff then
            buffsys_del(bctx, src, buff.uuid, ctx)
            buffsys_inherit(bctx, tobj, ctx, buff, src)
        end
    end
end
