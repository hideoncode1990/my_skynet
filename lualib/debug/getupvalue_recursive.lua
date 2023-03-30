local pairs = pairs
local getupvalue_byname = require "debug.getupvalue_byname"

return function(func, ...)
    for _, name in pairs({...}) do func = getupvalue_byname(func, name) end
    return func
end
