-- 自身血量
local to_ge<const> = 1 -- 过渡到大于等于
local to_le<const> = 2 -- 过渡到小于等于
local ge<const> = 3 -- 当前大于等于
local le<const> = 4 -- 当前小于等于

local opps_hp<const> = 1 -- 百分比血量
local fix_hp<const> = 2 -- 固定血量
local floor = math.floor

return function(bctx, self, tobj, ctx, parm, c_args)
    local stype, fix_or_opps, val = parm[1], parm[2], parm[3]
    assert(fix_or_opps == fix_hp or fix_or_opps == opps_hp, fix_or_opps)
    local hpmax = self.attrs.hpmax
    local hp = self.attrs.hp

    local now_val, target_val
    if fix_or_opps == opps_hp then
        now_val = floor(hp / hpmax * 100)
        target_val = floor(val / 1000 * 100)
    else
        now_val = hp
        target_val = val
    end

    if stype == to_ge or stype == to_le then
        local prior_hp = c_args.prior_hp
        local prior_val = fix_or_opps == fix_hp and prior_hp or
                              floor(prior_hp / hpmax * 100)
        if stype == to_ge then
            if prior_val >= target_val then return false end
        elseif stype == to_le then
            if prior_val <= target_val then return false end
        end
    end
    if stype == to_ge or stype == ge then
        if now_val >= target_val then return true end
    elseif stype == to_le or stype == le then
        if now_val <= target_val then return true end
    end
    return false
end

