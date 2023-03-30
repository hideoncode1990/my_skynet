local trigger = require "map.trigger"
local objmgr = require "map.objmgr"
local objtype = require "map.objtype"

return function(type)
    trigger.reg(type, {
        start = function(ctx, cfg)
            for _, v in ipairs(cfg.para) do
                local uuid, final_state = v[1], v[2]
                local o = objmgr.grab(uuid, objtype.door)
                o:execute(final_state)
            end
            trigger.finishctx(ctx)
        end
    })
end
