local trigger = require "map.trigger"
local timer = require "timer.second"
local utime = require "util.time"

return function(type)
    trigger.reg(type, {
        load = function(ctx, cfg)
            local ti = assert(cfg.para[1][1])
            ctx.expire = utime.time_int() + ti
        end,
        start = function(ctx)
            timer.addexpire(ctx.expire, function()
                trigger.finishctx(ctx)
            end)
        end
    })
end
