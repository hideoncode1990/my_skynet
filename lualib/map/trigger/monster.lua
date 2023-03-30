local trigger = require "map.trigger"
local monster_die = require "map.monster_die"
return function(type)
    trigger.reg(type, {start = trigger.finishctx})
    return function(cfg)
        return trigger.watch(cfg.id, function()
            if monster_die.logic(cfg.para, cfg.arg) then
                trigger.start(cfg.id)
                return true
            end
        end)
    end
end
