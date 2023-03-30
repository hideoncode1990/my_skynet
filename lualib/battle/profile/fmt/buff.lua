local fmt_total = "buffcost=%-4.2f"
local fmt_totalcnt = "total_cnt=%3d"
local fmt_delaycnt = "delay_cnt=%3d"
local fmt_intervalcnt = "interval_cnt=%3d"
local fmt_endcnt = "end_cnt=%3d"
return function(bctx, self)
    local pf = self.profile_data
    local total = pf.buff_cost or 0.001

    local delay_cnt = pf.buff_delaycnt or 0
    local up_cnt = pf.buff_intervalcnt or 0
    local end_cnt = pf.buff_endcnt or 0
    local totalcnt = delay_cnt + up_cnt + end_cnt

    local g_pf = bctx.profile_data
    g_pf.buff_effectcnt = (g_pf.buff_effectcnt or 0) + totalcnt

    local fmt = string.format(" ▍%s %s %s %s %s", fmt_total, fmt_totalcnt,
        fmt_delaycnt, fmt_intervalcnt, fmt_endcnt)

    return string.format(fmt, total, totalcnt, delay_cnt, up_cnt, end_cnt)
end
