local fmt_cast = "cast=%-5.2f "
local fmt_casting = "casting=%-5.2f"
local fmt_effectcnt = "effectcnt=%-3d"
local fmt_passivecost = "passivecost=%-5.2f(%3d)"
local fmt_calcdmg = "calcdmg=%-3.2f(%-3.2f)"
local fmt_applydmg = "applydmg=%-4.2f"

require "util"
return function(bctx, self)
    local pf = self.profile_data
    local castcost = pf.fsm_cast or 0.001

    local casting = pf.casting or 0
    local effectcnt = pf.effect_cnt or 0
    local passivecost = pf.passive_cost or 0
    local passivecnt = pf.passive_cnt or 0
    local calcdmg = pf.calc_damage or 0
    local calcbase = pf.calc_base or 0
    local applydmg = pf.apply_damage or 0

    ---[[
    if effectcnt > 100 then
        local e_cnts = pf.e_cnts or {}
        local e_costs = pf.e_costs or {}
        local effect_type = pf.effect_type
        local s = {}
        for k, v in pairs(e_costs) do
            if v > 1 then
                local _type = effect_type[k] or 0
                table.insert(s, string.format("%d(%d)=%f(%d)", k, _type, v,
                    e_cnts[k]))
            end
        end
        local s = table.concat(s, ',')
        print("effectcost", self.id, s)
    end
    -- ]]
    local fmt = string.format(" ▍%s %s %s %s %s %s", fmt_cast, fmt_casting,
        fmt_effectcnt, fmt_passivecost, fmt_calcdmg, fmt_applydmg)
    return string.format(fmt, castcost, casting, effectcnt, passivecost,
        passivecnt, calcdmg, calcbase, applydmg)
end
