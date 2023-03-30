local award = require "role.award"
local awardtype = require "role.award.type"
local uaward = require "util.award"
local hinit = require "hero"

return function(self, id, cnt, cfg)
    local costcnt = cfg.usepara[1][1]
    local cost = {{awardtype.items, id, cnt * costcnt}}
    local reward = {table.unpack(cfg.usepara, 2)} -- 第一个参数是数量, 后面是奖励
    reward = uaward().append(reward).multi(cnt).result
    local newtab = hinit.check_new_tab(self, reward)

    local ok, err = award.deladd(self,
        {flag = "item_use", arg1 = id, arg2 = cnt}, cost, reward)
    if not ok then return {e = err} end

    return {e = 0, items = reward, newtab = newtab}
end
