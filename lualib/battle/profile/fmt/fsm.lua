local fmt_fsm = "fsm=%-5.2f"
local fmt_idle = "[%-2d%%]idle=%-5.2f"
local fmt_move = "[%-2d%%]move=%-5.2f"
local fmt_cast = "[%-2d%%]cast=%-5.2f"
return function(bctx, self)
    local g_pf = bctx.profile_data
    local pf = self.profile_data
    local fsmcost = pf.fsm_cost or 0.001

    local fsmidle = pf.fsm_idle or 0
    local idle_ratio = math.floor(fsmidle / fsmcost * 100)
    g_pf.fsmdile = (g_pf.fsmdile or 0) + fsmidle

    local fsmmove = pf.fsm_move or 0
    local move_ratio = math.floor(fsmmove / fsmcost * 100)
    g_pf.fsmmove = (g_pf.fsmmove or 0) + fsmmove

    local fsmcast = pf.fsm_cast or 0
    local cast_ratio = math.floor(fsmcast / fsmcost * 100)
    g_pf.fsmcast = (g_pf.fsmcast or 0) + fsmcast

    local fmt = string.format(" ▍%s %s %s %s", fmt_fsm, fmt_idle, fmt_move,
        fmt_cast)

    return string.format(fmt, fsmcost, idle_ratio, fsmidle, move_ratio, fsmmove,
        cast_ratio, fsmcast)
end
