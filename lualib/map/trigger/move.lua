local trigger = require "map.trigger"
return function(type)
    trigger.reg(type, {start = trigger.finishctx})
    return function(cfg)
        return trigger.watch(cfg.id, function(pos)
            if cfg.para[1][1] == pos then
                trigger.start(cfg.id)
                return true
            end
        end)
    end
end
