local trigger = require "map.trigger"
local objmgr = require "map.objmgr"

return function(type)
    trigger.reg(type, {
        load = function(_, cfg)
            for _, c in pairs(cfg.para) do
                objmgr.create(table.unpack(c))
            end
        end,
        start = trigger.finishctx
    })
end
