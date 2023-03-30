local skynet = require "skynet"
local base = require "cfg.base"

local function create_proxy(nm, t)
    local d = base.CACHES[nm]
    return setmetatable(t, {
        __tostring = function()
            return "proxy:" .. nm
        end,
        __index = d,
        __newindex = error,
        __len = function()
            return #d
        end,
        __pairs = function()
            return pairs(d)
        end
    })
end

local cache = {}
base.onchangeall(function(changes)
    for k in pairs(changes) do
        local p = cache[k]
        if p then
            skynet.error("reproxy", p, k)
            create_proxy(k, p)
        end
    end
end, "proxy")

local function proxy(nm)
    local t = cache[nm]
    if t then
        return t
    else
        t = create_proxy(nm, {})
        if cache[nm] then
            t = cache[nm]
        else
            cache[nm] = t
        end
        return t
    end
end

return function(...)
    local ret = {}
    for _, nm in ipairs({...}) do table.insert(ret, proxy(nm)) end
    return table.unpack(ret)
end
