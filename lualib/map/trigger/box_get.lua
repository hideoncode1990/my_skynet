local trigger = require "map.trigger"
local env = require "map.env"
local utable = require "util.table"
local box_opened = require "map.box_opened"

return function(type)
    trigger.reg(type, {start = trigger.finishctx})
    return function(cfg)
        trigger.watch(cfg.id, function()
            if box_opened.logic(cfg.para) then trigger.start(cfg.id) end
        end)
    end
end

