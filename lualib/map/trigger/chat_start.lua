local trigger = require "map.trigger"
local chat = require "map.chat"
return function(type)
    trigger.reg(type, {
        load = function(_, cfg)
            local chat_id = assert(cfg.para[1][1])
            if chat.check_played(chat_id) then return end
            assert(chat.start(chat_id, chat.type.passive))
        end,
        start = trigger.finishctx
    })
end
