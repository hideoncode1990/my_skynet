local award = require "role.award"
local awardtype = require "role.award.type"
local drop = require "role.drop"
local hinit = require "hero"

return function(self, id, cnt, cfg)
    local costcnt = cfg.usepara[1][1]

    local cost = {{awardtype.items, id, cnt * costcnt}}

    local ok, err = award.checkdel(self, cost)
    if not ok then return {e = err} end

    local reward = drop.calc(cfg.usepara[2][1], cnt)
    local newtab = hinit.check_new_tab(self, reward)

    ok, err = award.deladd(self, {flag = "item_use", arg1 = id, arg2 = cnt},
        cost, reward)
    if not ok then return {e = err} end

    return {e = 0, items = reward, newtab = newtab}
end
