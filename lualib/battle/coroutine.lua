local skynet = require "skynet"
local timer = require "timer"
local _M = {}

local inwait = {}
function _M.wait(bctx, co, level, ti, args)
    assert(not inwait[co])
    local tid = timer.add(ti, function()
        _M.wakeup(bctx, co, level, args)
    end)
    inwait[co] = level
    skynet.wait(co)
    inwait[co] = nil
    timer.del(tid)
end

function _M.wakeup(bctx, co, level, args)
    level = level or 1
    local lv = inwait[co] or 0
    if level <= lv then
        if args then if args.terminate then bctx.terminate = true end end
        skynet.wakeup(co)
    end
end

return _M
