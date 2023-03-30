local trigger = require "map.trigger"

return function(type)
    trigger.reg(type, {
        start = function(_)
            print("trigger exit happen~!")
        end
    })
end
