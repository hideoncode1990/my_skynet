local heroclass = require "battle.class.hero"
local _M = setmetatable({}, {
    __call = function(_, ...)
        return heroclass.init(...)
    end
})

return _M
