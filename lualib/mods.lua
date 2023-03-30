local logerr = require "log.err"

local error = error
local ipairs = ipairs
local traceback = debug.traceback
local xpcall = xpcall

return function()

    local NAME2MOD = {}
    local MODS = {}

    local _M = {}

    function _M.reg(mod, name)
        name = name or mod.name
        assert(name and mod)
        if NAME2MOD[name] then error("dumplicate module " .. name) end
        NAME2MOD[name] = mod
        table.insert(MODS, mod)
    end

    function _M.rereg(mod, name)
        name = name or mod.name
        assert(name and mod)
        local mod_old = NAME2MOD[name]
        if not mod_old then
            _M.reg(mod, name)
        else
            for i, m in ipairs(MODS) do
                if mod_old == m then
                    table.remove(MODS, i)
                    table.insert(MODS, i, mod)
                    NAME2MOD[name] = mod
                    return mod_old
                end
            end
            error("data error")
        end
    end

    function _M.call(n, ...)
        for _, mod in ipairs(MODS) do
            local func = mod[n]
            if func then
                local ok, err = xpcall(func, traceback, ...)
                if not ok then logerr(err) end
            end
        end
    end

    function _M.call_revert(n, ...)
        for i = #MODS, 1, -1 do
            local func = MODS[i][n]
            if func then
                local ok, err = xpcall(func, traceback, ...)
                if not ok then logerr(err) end
            end
        end
    end

    function _M.get(_, name)
        return NAME2MOD[name]
    end

    return _M
end
