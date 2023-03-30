local trigger = require "map.trigger"
local objmgr = require "map.objmgr"

return function(type)
    trigger.reg(type, {
        start = function(ctx, cfg)
            local para, total = cfg.para, 0
            for _, v in ipairs(para) do total = total + v[2] end
            local ran = math.random(1, total)
            local temp = 0
            for _, v in ipairs(para) do
                temp = temp + v[2]
                if temp >= ran then
                    trigger.start(v[1])
                    break
                end
            end
            trigger.finishctx(ctx, cfg)
        end
    })
end
