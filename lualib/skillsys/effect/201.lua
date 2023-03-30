--[[
添加/删除一个buff
]] local buffsys = require "skillsys.buffsys"
local get_buff_by_cfgid = buffsys.get_buff_by_cfgid
local buffsys_del = buffsys.del
local buffsys_add = buffsys.add
local utable = require "util.table"
local utable_copy = utable.copy

return function(bctx, src, ctx, tobj, ecfg, e_args, negative_effect)
    local parm = ecfg.parm
    local buffid = parm[1]
    if negative_effect then
        local buff = get_buff_by_cfgid(tobj, buffid)
        if buff then buffsys_del(bctx, tobj, buff.uuid, ctx) end
        return
    end
    local buff_ctx
    if e_args and e_args.buff_ctx then
        buff_ctx = utable_copy(e_args.buff_ctx) -- 避免不同buff共用ctx
    end
    if parm[2] then
        if not buff_ctx then buff_ctx = {} end
        buff_ctx.times = parm[2]
    end
    buffsys_add(bctx, tobj, ctx, buffid, src, buff_ctx)
end
