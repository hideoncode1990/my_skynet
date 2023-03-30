local unpack = table.unpack
local insert = table.insert
local floor = math.floor
local ipairs = ipairs

local _M = {}

function _M.pack(awards)
    local ret = {}
    for _, a in ipairs(awards) do insert(ret, {item = a}) end
    return ret
end

local concat = table.concat
local select = select

local function calc(_result)
    local cache = {}
    local result

    local function key(a)
        local a1, a2 = a[1], a[2]
        local ak
        if #a > 3 then
            ak = a1 .. "|" .. a2 .. "|" .. concat(a, "|", 4)
        else
            ak = a1 .. "|" .. a2
        end
        return ak
    end

    if _result then
        result = _result
        for _, a in ipairs(_result) do
            local ak = key(a)
            cache[ak] = a
        end
    else
        result = {}
    end

    local ctx = {result = result}

    local function append_inner(a)
        local ak = key(a)
        local c = cache[ak]
        if c then
            c[3] = c[3] + a[3]
        else
            c = {unpack(a)}
            insert(result, c)
            cache[ak] = c
        end
        return ctx
    end

    ctx.append_one = function(...)
        local n = select("#", ...)
        for i = 1, n do
            local a = select(i, ...)
            if a then append_inner(a) end
        end
        return ctx
    end

    ctx.append = function(...)
        local n = select("#", ...)
        for i = 1, n do
            local ars = select(i, ...)
            if ars then
                for _, a in ipairs(ars) do append_inner(a) end
            end
        end
        return ctx
    end

    ctx.multi = function(cnt)
        for _, a in ipairs(result) do a[3] = floor(a[3] * cnt) end
        return ctx
    end

    ctx.append_ctx = function(nctx)
        return ctx.append(nctx.result)
    end

    ctx.pack = function()
        local ret = {}
        for _, a in ipairs(result) do insert(ret, {item = a}) end
        return ret
    end

    ctx.getcnt = function(type)
        local cnt = 0
        for _, a in ipairs(result) do
            if a[1] == type then cnt = cnt + a[3] end
        end
        return cnt
    end

    ctx.insert = function(tbl)
        for _, a in ipairs(tbl) do insert(result, a) end
        return ctx
    end
    ctx.insert_one = function(one)
        insert(result, one)
        return ctx
    end

    return ctx
end

setmetatable(_M, {
    __call = function(_, ...)
        return calc(...)
    end
})

return _M
