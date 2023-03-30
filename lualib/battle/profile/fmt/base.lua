local str_base =
    "profile: %-10d frame=%-3d total=%-5.2f fsm=%-5.2f buff=%-5.2f "
return function(bctx, self)
    local pf = self.profile_data
    local frame = bctx.btime.frame
    local total = pf.total_cost
    local fsmcost = pf.fsm_cost or 0
    local buffcost = pf.buff_cost or 0
    local s_base = string.format(str_base, self.id, frame, total, fsmcost,
        buffcost)
    -- base
    return s_base
end
