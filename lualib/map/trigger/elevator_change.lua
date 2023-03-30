local trigger = require "map.trigger"
local objmgr = require "map.objmgr"
local objtype = require "map.objtype"

return function(type)
    trigger.reg(type, {start = trigger.finishctx})
    return function(cfg)
        return trigger.watch(cfg.id, function()
            if objmgr.logic(cfg.para, objtype.elevator, function(o)
                return o.times
            end) then
                trigger.start(cfg.id)
                return true
            end
        end)
    end
end
