-- 自身血量百分比变化
local floor = math.floor

return function(bctx, self, tobj, ctx, parm, c_args)
    local hpmax = self.attrs.hpmax
    local prior_hp = assert(c_args.prior_hp)
    local prior_opps = floor(prior_hp / hpmax * 100)
    local now_hp = self.attrs.hp
    local now_opps = floor(now_hp / hpmax * 100)
    return prior_opps ~= now_opps
end

