local trigger = require "map.trigger"
return function(type)
    trigger.reg(type, {start = trigger.finishctx})
    return function(cfg)
        return trigger.watch(cfg.id, function(uuid)
            if uuid == cfg.para[1][1] then
                trigger.start(cfg.id)
                return true
            end
        end)
    end
end
