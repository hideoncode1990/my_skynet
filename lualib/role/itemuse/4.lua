local award = require "role.award"
local awardtype = require "role.award.type"
local generator = require "role.award.generate"
local mainline = require "role.m_mainline"
local hinit = require "hero"

return function(self, id, cnt, cfg)
    local cost = {{awardtype.items, id, cnt}}
    local reward = mainline.itemuse(self, cfg.usepara, cnt)
    if not reward then return {e = 401} end

    reward = generator.gen(reward)
    local newtab = hinit.check_new_tab(self, reward)

    local ok, err = award.deladd(self,
        {flag = "item_use", arg1 = id, arg2 = cnt}, cost, reward)
    if not ok then return {e = err} end
    return {e = 0, items = reward, newtab = newtab}
end
