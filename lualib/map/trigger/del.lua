local objmgr = require "map.objmgr"
local trigger = require "map.trigger"
return function(type)
    trigger.reg(type, {
        start = function(ctx, cfg)
            local del_uuids = cfg.para[1]
            for _, uuid in ipairs(del_uuids) do
                assert(objmgr.check_obj(uuid))
                objmgr.del(uuid)
            end
            trigger.finishctx(ctx, cfg)
        end
    })
end
