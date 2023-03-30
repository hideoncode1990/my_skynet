local str_target = "findtarget=%-5.2f(%3d) "
return function(bctx, self)
    local pf = self.profile_data
    local findtargetcost = pf.idle_findtarget or 0
    local findtargetcnt = pf.idle_findtargetcnt or 0
    local s_target = string.format(str_target, findtargetcost, findtargetcnt)
    -- target
    return s_target
end
