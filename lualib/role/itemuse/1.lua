local award = require "role.award"
local awardtype = require "role.award.type"
local generator = require "role.award.generate"
local uaward = require "util.award"
local hinit = require "hero"

return function(self, id, cnt, cfg)
    local cost = {{awardtype.items, id, cnt}}
    local result = uaward().append(cfg.usepara).multi(cnt).result
    local reward = generator.gen(result)
    local newtab = hinit.check_new_tab(self, reward)

    local ok, err = award.deladd(self,
        {flag = "item_use", arg1 = id, arg2 = cnt}, cost, reward)
    if not ok then return {e = err} end
    return {e = 0, items = reward, newtab = newtab}
end
