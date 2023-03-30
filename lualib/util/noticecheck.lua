local ext = require "ext.c"
local words = require "words"

return function(oname, limit)
    local name = ext.name_trim(oname)
    local len = utf8.len(name)
    if len < limit[1] then return false, 1 end
    if len > limit[2] then return false, 2 end
    if name == "" then return name end
    if not words.dirtycheck(name) then return false, 3 end
    return name
end
