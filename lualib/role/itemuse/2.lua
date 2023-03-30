local award = require "role.award"
local awardtype = require "role.award.type"
local generator = require "role.award.generate"
local utable = require "util.table"
local drop = require "role.drop"
local hinit = require "hero"

local mixture = utable.mixture

return function(self, id, cnt, cfg)
    local cost = {{awardtype.items, id, cnt}}
    local list = {}

    local ok, err = award.checkdel(self, cost)
    if not ok then return {e = err} end

    for _, v in ipairs(cfg.usepara) do
        local did = v[1]
        mixture(list, drop.calc(did, cnt))
    end
    local reward = generator.gen(list)
    local newtab = hinit.check_new_tab(self, reward)

    ok, err = award.deladd(self, {flag = "item_use", arg1 = id, arg2 = cnt},
        cost, reward)
    if not ok then return {e = err} end
    return {e = 0, items = reward, newtab = newtab}
end
