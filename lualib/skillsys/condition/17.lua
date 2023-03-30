-- 自身拥有指定buff
local buffsys = require "skillsys.buffsys"
local get_buff_by_cfgid = buffsys.get_buff_by_cfgid
local get_buff_by_type = buffsys.get_buff_by_type
local check_control_buff = buffsys.check_control_buff
local check_exist_bygroup = buffsys.check_exist_bygroup

local subtype_buffid<const> = 1 -- buff cfgid
local subtype_buff_type<const> = 2 -- buff type(增益，减益,护盾)
local subtype_control<const> = 3 -- 控制类型
local subtype_group<const> = 4 -- buff group
local subtype_argid<const> = 5 -- 传递的buffid

return function(bctx, self, tobj, ctx, parm, c_args)
    local stype, id = parm[1], parm[2]
    if stype == subtype_buffid then
        if get_buff_by_cfgid(self, id) then return true end
    elseif stype == subtype_buff_type then
        if get_buff_by_type(self, id) then return true end
    elseif stype == subtype_control then
        if check_control_buff(self, id) then return true end
    elseif stype == subtype_group then
        if check_exist_bygroup(self, id) then return true end
    elseif stype == subtype_argid then
        if c_args.buffid == id then return true end
    end
    return false
end
