local fmt_fsmidle = "idle=%-4.2f"
local fmt_gettar = "gettar=%-4.2f"
local fmt_fintarget = "fintar=%-4.2f(%-3d)"
local fmt_checkcast = "checkcast=%-4.2f"
local fmt_entercast = "entercast=%-4.2f(%-3d)"
local fmt_startmove = "startmove=%-4.2f(%2d/%-3d)"
local fmt_movefail = "movefail=%4.2f"
return function(bctx, self)
    local pf = self.profile_data
    local idlecost = pf.idle_total or 0.001

    -- local gettarget = pf.idle_gettarget or 0
    local findtarget = pf.idle_findtarget or 0
    local findtargetcnt = pf.idle_findtargetcnt or 0

    -- local checkcast = pf.idle_checkcast or 0
    local entercast = pf.idle_entercast or 0
    local entercastcnt = pf.idle_entercastcnt or 0
    -- local startmovecost = pf.idle_startmovecost or 0
    -- local startmovecnt = pf.idle_startmovecnt or 0
    -- local startmovesucc = pf.idle_startmovesucc or 0
    -- local movefail = pf.idle_startmovefail or 0

    local fmt = string.format("▍%s %s %s", fmt_fsmidle, fmt_fintarget,
        fmt_entercast)

    return string.format(fmt, idlecost, findtarget, findtargetcnt, entercast,
        entercastcnt)
end
