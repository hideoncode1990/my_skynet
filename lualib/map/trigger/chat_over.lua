local trigger = require "map.trigger"
return function(type)
    trigger.reg(type, {start = trigger.finishctx})
    return function(cfg)
        trigger.watch(cfg.id, function(chat_id, index)
            if chat_id == cfg.para[1][1] then
                trigger.start(cfg.id)
                local choice = cfg.para[2]
                if choice then
                    trigger.start(assert(choice[index]))
                end
                return true
            end
        end)
    end
end
