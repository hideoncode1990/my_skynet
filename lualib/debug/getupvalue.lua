local getupvalue_byname = require "debug.getupvalue_byname"
local table = table
local pairs = pairs

return function(func, ...)
    local ret = {}
    for _, name in pairs({...}) do
        table.insert(ret, (getupvalue_byname(func, name)))
    end
    return table.unpack(ret)
end
