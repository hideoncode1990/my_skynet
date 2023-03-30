local _M = {}

local assert = assert
local insert = table.insert
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local tonumber = tonumber

function _M.OBJ(def)
    return function(encode, d)
        d = d or {}
        local s = {}
        for k, c in pairs(def) do
            local v = d[k]
            s[k] = c(encode, v)
        end
        return s
    end
end

function _M.ARR(def)
    return function(encode, d)
        local s = {}
        for k, v in pairs(d or {}) do insert(s, def(encode, v, k)) end
        return s
    end
end

function _M.NOBJ(def)
    if not def then
        return function(encode, d)
            local s = {}
            if encode then
                for k, v in pairs(d or {}) do s[tostring(k)] = v end
            else
                for k, v in pairs(d or {}) do s[tonumber(k)] = v end
            end
            return s
        end
    else
        return function(encode, d)
            local s = {}
            if encode then
                for k, v in pairs(d or {}) do
                    s[tostring(k)] = def(encode, v, k)
                end
            else
                for k, v in pairs(d or {}) do
                    s[tonumber(k)] = def(encode, v, k)
                end
            end
            return s
        end
    end
end

function _M.MAPF(f, def)
    if not def then
        return function(encode, d)
            local s = {}
            if encode then
                for _, v in pairs(d or {}) do
                    assert(v[f])
                    insert(s, v)
                end
            else
                for _, v in ipairs(d or {}) do
                    local k = v[f]
                    s[k] = v
                end
            end
            return s
        end
    else
        return function(encode, d)
            local s = {}
            if encode then
                for k, v in pairs(d or {}) do
                    assert(v[f])
                    insert(s, (def(encode, v, k)))
                end
            else
                for k, v in pairs(d or {}) do
                    local _k = v[f]
                    s[_k] = def(encode, v, k)
                end
            end
            return s
        end
    end
end

function _M.SAR(def)
    if not def then
        return function(encode, d)
            if encode then
                local ks, vs = {}, {}
                for k, v in pairs(d or {}) do
                    insert(ks, k)
                    insert(vs, v)
                end
                return {ks = ks, vs = vs}
            else
                local ks, vs
                if not d then
                    ks, vs = {}, {}
                else
                    ks, vs = d.ks or {}, d.vs or {}
                end
                local s = {}
                for i, k in ipairs(ks) do
                    local v = vs[i]
                    s[k] = v
                end
                return s
            end
        end
    else
        return function(encode, d)
            if encode then
                local ks, vs = {}, {}
                for k, v in pairs(d or {}) do
                    insert(ks, k)
                    insert(vs, (def(encode, v, k)))
                end
                return {ks = ks, vs = vs}
            else
                local ks, vs
                if not d then
                    ks, vs = {}, {}
                else
                    ks, vs = d.ks, d.vs
                end
                local s = {}
                for i, k in ipairs(ks) do
                    local v = vs[i]
                    s[k] = def(encode, v, k)
                end
                return s
            end
        end
    end
end

function _M.SET(def)
    if not def then
        return function(encode, d)
            local s = {}
            if encode then
                for k in pairs(d or {}) do insert(s, k) end
            else
                for _, v in ipairs(d or {}) do s[v] = true end
            end
            return s
        end
    else
        return function(encode, d)
            local s = {}
            if encode then
                for k in pairs(d or {}) do
                    insert(s, def(encode, k))
                end
            else
                for _, v in ipairs(d or {}) do
                    s[def(encode, v)] = true
                end
            end
            return s
        end
    end
end

function _M.ORI(_, d)
    return d
end

function _M.STR(_, d)
    return tostring(d)
end

function _M.NUM(_, d)
    return tonumber(d)
end

return _M
