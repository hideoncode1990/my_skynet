local commanderclass = require "battle.class.commander"
local _M = setmetatable({}, {
    __call = function(_, ...)
        return commanderclass.init(...)
    end
})

return _M

