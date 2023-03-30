local fmt_findpath = "findpath=%-5.2f"
local fmt_startmovecnt = "(%2d/%-3d)"
local fmt_checkdist = "checkdist=%-5.2f"
local fmt_surround = "surround=%-5.2f(%3d)"
local fmt_findline = "findline=%-5.2f(%3d)"
local fmt_astar = "astar=%-5.2f(%3d)"
local fmt_other = "other=%-5.2f"
return function(bctx, self)
    local pf = self.profile_data
    local startmove_findpath = pf.startmove_findpath or 0.001
    local startmovecnt = pf.idle_startmovecnt or 0
    local startmovesucc = pf.idle_startmovesucc or 0

    local checkdist = pf.move_checkdist or 0
    local surround = pf.move_surround or 0
    local surroundcnt = pf.move_surroundcnt or 0
    local findline = pf.move_findline or 0
    local findlinecnt = pf.move_findlinecnt or 0
    local astar = pf.move_astar or 0
    local astarcnt = pf.move_astarcnt or 0
    local other = pf.move_other or 0

    local fmt = string.format(" ▍%s%s %s %s %s %s %s", fmt_findpath,
        fmt_startmovecnt, fmt_checkdist, fmt_surround, fmt_findline, fmt_astar,
        fmt_other)
    return string.format(fmt, startmove_findpath, startmovesucc, startmovecnt,
        checkdist, surround, surroundcnt, findline, findlinecnt, astar,
        astarcnt, other)
end
