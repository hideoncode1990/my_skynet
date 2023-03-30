local triggerclass = require "battle.class.trigger"
local _M = setmetatable({}, {
    __call = function(_, ...)
        return triggerclass.init(...)
    end
})

return _M

