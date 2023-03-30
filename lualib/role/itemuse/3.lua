local award = require "role.award"
local awardtype = require "role.award.type"
local generator = require "role.award.generate"
local uaward = require "util.award"
local hinit = require "hero"

local insert = table.insert

return function(self, id, cnt, cfg, args)
    local cost = {{awardtype.items, id, cnt}}
    local usepara = cfg.usepara
    local num = usepara[1][1]

    local reward = {}
    if num == 1 then
        local sum = 0
        for _, v in ipairs(args) do
            local order, count = v[1], v[2]
            assert(count > 0)
            sum = sum + count
            local item_cfg = usepara[order + 1]
            insert(reward, {item_cfg[1], item_cfg[2], item_cfg[3] * count})
        end
        if sum ~= cnt then return {e = 301} end

        reward = generator.gen(reward)
    else
        for _, order in ipairs(args) do
            insert(reward, usepara[order + 1])
        end

        reward = generator.gen(uaward().append(reward).multi(cnt).result)
    end
    local newtab = hinit.check_new_tab(self, reward)

    local ok, err = award.deladd(self,
        {flag = "item_use", arg1 = id, arg2 = cnt}, cost, reward)
    if not ok then return {e = err} end

    return {e = 0, items = reward, newtab = newtab}
end
