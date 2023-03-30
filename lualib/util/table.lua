local pairs = pairs
local type = type
local insert = table.insert

local _M = {}

local function tcopy(t)
    local r = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            r[k] = tcopy(v)
        else
            r[k] = v
        end
    end
    return r
end

local function getsub(S, K, ...)
    if K == nil then return S end
    local s = S[K]
    if not s then
        s = {}
        S[K] = s
    end
    return getsub(s, ...)
end

function _M.sub(S, K)
    local s = S[K]
    if not s then
        s = {}
        S[K] = s
    end
    return s
end

function _M.mixture(target, source)
    for _, v in ipairs(source) do insert(target, v) end
    return target
end

_M.copy = tcopy
_M.getsub = getsub

function _M.logic(tbl, condi)
    for _, args in ipairs(condi) do
        local ret = true
        for _, id in ipairs(args) do
            local ctx = tbl[id]
            if not ctx then
                ret = false
                break
            end
        end
        if ret then return true end
    end
    return false
end

function _M.array_find(t, _v)
    for i, v in ipairs(t) do if v == _v then return i end end
end

function _M.irspairs(t)
    local max, idx = #t, 1
    local start = math.random(1, math.max(1, max))
    return function()
        local cur = idx
        if cur > max then return end
        local i = (cur + start)
        if i > max then i = i - max end
        idx = idx + 1
        return cur, t[i]
    end
end

return _M
