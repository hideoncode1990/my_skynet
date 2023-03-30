local trigger = require "map.trigger"
local objmgr = require "map.objmgr"
local objtype = require "map.objtype"

return function(type)
    trigger.reg(type, {
        start = function(ctx, cfg)
            local ret = {}
            for _, v in ipairs(cfg.para) do
                local uuid, id = v[1], v[2]
                local o = objmgr.grab(uuid, objtype.monster)
                if o then ret[o] = {o.change_check(id)} end
            end

            for o, v in pairs(ret) do o:change_id(table.unpack(v)) end

            trigger.finishctx(ctx)
        end
    })
end
