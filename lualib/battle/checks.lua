local types = require "battle.limit"

local call = {
    auto = function(limit, v)
        local bit = v and types.auto or types.manual
        local isset = limit & bit
        return isset == 0
    end
}

local _M = {}

function _M.check(limit, tp, v)
    local f = call[tp]
    if f then return f(limit, v) end
    local bit = assert(types[tp], tp)
    local isset = limit & bit
    return isset == 0
end

--[[
    auto    manual
    0       0       --可自动可手动
    0       1       --禁手动
    1       0       --禁自动
    1       1       --录像状态
]]

function _M.calc_auto(limit, v)
    local bit = types.auto | types.manual
    local allset = limit & bit
    if allset == 1 then
        return false
    elseif allset == 2 then
        return true
    else
        return v or false
    end
end

return _M
