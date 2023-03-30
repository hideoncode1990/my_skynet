--[[
    释放指定技能
]] return function(bctx, src, ctx, tobj, ecfg)
    src:set_skill_queue({table.unpack(ecfg.parm)})
    local parm2 = ecfg.parm2
    local need_target = parm2 and parm2[1]
    if need_target then src:set_target(tobj) end
end
