local log = require "log"

local math_random = math.random
local tremove = table.remove
local tinsert = table.insert
local _M = {}

function _M.set_random(f)
    math_random = assert(f)
end

function _M.new(p)
    local all, count = 0, 0
    local pdf, name, name_list = {}, {}, {}

    for k, v in pairs(p) do
        all, count = all + v, count + 1
        name[count], pdf[count] = k, v
        tinsert(name_list, k)
    end

    local average = all / count
    local probability, alias = {}, {}
    local small, large = {}, {}
    for i, v in ipairs(pdf) do
        if v >= average then
            tinsert(large, i)
        else
            tinsert(small, i)
        end
    end

    while #small > 0 and #large > 0 do
        local less, more = tremove(small), tremove(large)
        probability[less] = pdf[less] * count
        alias[less] = more
        pdf[more] = pdf[more] + pdf[less] - average
        if pdf[more] >= average then
            tinsert(large, more)
        else
            tinsert(small, more)
        end
    end
    assert(count>0)
    while #small > 0 do probability[tremove(small)] = all end
    while #large > 0 do probability[tremove(large)] = all end

    return {
        alias = alias,
        probability = probability,
        count = count,
        all = all,
        name = name,
        name_list = name_list
    }
end

function _M.news(...)
    local all, count = 0, 0
    local pdf, name = {}, {}
    for _, p in ipairs {...} do
        for k, v in pairs(p) do
            all, count = all + v, count + 1
            name[count], pdf[count] = k, v
        end
    end
    local average = all / count
    local probability, alias = {}, {}
    local small, large = {}, {}
    for i, v in ipairs(pdf) do
        if v >= average then
            tinsert(large, i)
        else
            tinsert(small, i)
        end
    end

    while #small > 0 and #large > 0 do
        local less, more = tremove(small), tremove(large)
        probability[less] = pdf[less] * count
        alias[less] = more
        pdf[more] = pdf[more] + pdf[less] - average
        if pdf[more] >= average then
            tinsert(large, more)
        else
            tinsert(small, more)
        end
    end
    assert(count>0)
    while #small > 0 do probability[tremove(small)] = all end
    while #large > 0 do probability[tremove(large)] = all end

    return {
        alias = alias,
        probability = probability,
        count = count,
        all = all,
        name = name
    }
end

local function nexts(data)
    local col = math_random(1, data.count)
    local all = data.all
    local ok = (math_random(1, all) - 1) < data.probability[col]
    local id = ok and col or data.alias[col]
    return data.name[id]
end

_M.nexts = nexts

function _M.multi(data, cnt)
    assert(cnt > 0)
    if cnt >= data.count then
        return data.name_list
    else
        local i, result, num = 0, {}, 0
        local temp = {}
        while num < cnt do
            if i >= 2000 then
                log("multi random failure")
                assert(false)
            end
            local k = nexts(data)
            i = i + 1
            if not temp[k] then
                table.insert(result, k)
                temp[k] = true
                num = num + 1
            end
        end
        return result
    end
end

return _M
