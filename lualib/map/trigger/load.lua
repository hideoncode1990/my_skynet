local trigger = require "map.trigger"

return function(type)
    trigger.reg(type, {
        start = function(ctx)
            print("load start", ctx)
            trigger.finishctx(ctx)
        end
    })

    return function(cfg)
        trigger.watch(cfg.id, function()
            print("load", cfg.id)
            trigger.start(cfg.id)
        end)
    end
end
