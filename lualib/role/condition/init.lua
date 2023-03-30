local ipairs = ipairs
local table = table
local _M = {}

local checks = {}
function _M.reg(type, call)
    checks[type] = call
end

local function logic_and(self, args)
    for _, arg in ipairs(args) do
        local type = arg[1]
        local cb = assert(checks[type])
        if not cb(self, table.unpack(arg, 2)) then return false end
    end
    return true
end

local function logic_or(self, param)
    for _, args in ipairs(param) do
        if logic_and(self, args) then return true end
    end
    return false
end

function _M.check(self, param)
    return logic_or(self, param)
end

return _M
