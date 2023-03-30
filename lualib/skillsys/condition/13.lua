-- 目标印记层数
local attr_ids = require"util.attrs".ids
local to_ge<const> = 1 -- 过渡到大于等于
local eq<const> = 2 -- 等于
local ge<const> = 3 -- 大于等于

return function(bctx, self, tobj, ctx, parm, c_args)
    if not tobj then return false end
    local stype, id, num = parm[1], parm[2], parm[3]
    local attrs = tobj.attrs
    local key = assert(attr_ids[id], id)
    local now_signet = attrs[key]
    if stype == to_ge then
        if id == c_args.signet_id then
            local prior_signet = c_args.prior_signet
            if prior_signet < num and now_signet >= num then
                return true
            end
        end
    elseif stype == eq then
        return num == now_signet
    elseif stype == ge then
        return now_signet >= num
    end
    return false
end
