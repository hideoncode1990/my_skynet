local trigger = require "map.trigger"
local record = require "map.record"

return function(type)
    trigger.reg(type, {
        start = function(ctx, cfg)
            for _, v in ipairs(cfg.para) do record.add(v[1]) end
            trigger.finishctx(ctx)
        end
    })
end

