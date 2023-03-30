local INFO = {
    ["function"] = function(v)
        local info = debug.getinfo(v)
        local src = info.short_src
        local line = info.linedefined
        return string.format("%s--[[%s:%d]]", v, src, line)
    end
}

local function infostring(v)
    local types = type(v)
    local call = INFO[types] or tostring
    return call(v), types
end

local PROXY = {
    ["table"] = function(v)
        local ret = {}
        for k, _v in next, v do table.insert(ret, {k, _v}) end
        local mt = getmetatable(v)
        if mt then table.insert(ret, {"__metatable", mt}) end
        return ret
    end,
    ["function"] = function(v)
        local ret = {}
        for i = 1, math.maxinteger do
            local name, value = debug.getupvalue(v, i)
            if not name then break end
            table.insert(ret, {name, value})
        end
        return ret
    end,
    ["userdata"] = function(v)
        local mt = getmetatable(v)
        if mt then
            return {{"__metatable", mt}}
        else
            return {}
        end
    end,
    ["thread"] = function(v)
        local ret = {}
        for i = 0, math.maxinteger do
            local info = debug.getinfo(v, i, "flnStu")
            if not info then break end
            local key = string.format("%d %s %s(%s:%d)", i, info.what or "nil",
                                      info.name, info.short_src,
                                      info.currentline)
            table.insert(ret, {key, info.func})
            for j = 1, math.maxinteger do
                local name, val = debug.getlocal(v, i, j)
                if not name then break end
                table.insert(ret, {string.format("-->%d local %s", j, name), val})
            end
        end
        return ret
    end
}

local function tblinfo(tbl)
    local ret = {}
    for _, v in pairs(tbl) do
        table.insert(ret, {infostring(v[1]), infostring(v[2])})
    end
    return ret
end

return function(root, ...)
    local keys = {}
    local function getsub(S, K, ...)
        if K == nil then return tblinfo(S) end
        table.insert(keys, K)
        local s
        for _, v in ipairs(S) do
            if infostring(v[1]) == K then
                s = v[2]
                break
            end
            -- if infostring(v) == K then
            --     s = v
            --     break
            -- end
        end

        local proxy = PROXY[type(s)]
        if proxy then
            return getsub(proxy(s), ...)
        else
            return infostring(s)
        end
    end
    return keys, getsub(PROXY.table(root or {}), ...)
end
