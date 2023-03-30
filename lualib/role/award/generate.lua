local skynet = require "skynet"
local udrop = require "util.drop"
local uaward = require "util.award"
local cfgproxy = require "cfg.proxy"
local awardtype = require "role.award.type"
local CFG = {}

skynet.init(function()
    CFG = cfgproxy("equip")
end)

local _GEN = {
    [awardtype.equip] = function(ctx, cfg)
        if #cfg == 3 then
            local id, cnt = cfg[2], cfg[3]
            for _ = 1, cnt do
                local feature = udrop.nexts(CFG[id].feature_random)
                ctx.append_one({awardtype.equip, id, 1, feature})
            end
        else
            ctx.append_one(cfg)
        end
    end
}

local _M = {}

function _M.gen(awards)
    local ctx = uaward()
    for _, award in ipairs(awards) do
        local type = award[1]
        local gen = _GEN[type]
        if gen then
            gen(ctx, award)
        else
            ctx.append_one(award)
        end
    end
    return ctx.result
end

function _M.feature(id)
    local feature = udrop.nexts(CFG[id].feature_random)
    return feature ~= 0 and feature or nil
end

function _M.re_feature(id, prefeature)
    local featab, weighttab, weight = {}, {}, 0
    for _, v in ipairs(CFG[id].feature) do
        local feature = v[1]
        if feature ~= 0 and feature ~= prefeature then
            table.insert(featab, feature)
            weight = weight + v[2]
            table.insert(weighttab, weight)
        end
    end
    local ran = math.random(1, weight)
    for i, feature in ipairs(featab) do
        if ran <= weighttab[i] then return feature end
    end
    assert(false)
end

return _M
