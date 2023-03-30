local cfgdata = require "cfg.data"
local skynet = require "skynet"
local bco = require "battle.coroutine"
local cfg
skynet.init(function()
    cfg = cfgdata.basic.multspeed
end)
return function()
    local _M = {now = 0, frame = 0, ispause = false}
    local timestamp = 0
    local timestop = 0
    local pause = false
    local combo_ti = 0

    local granule_init = 20
    local granule = granule_init

    local frame_time = 20 -- 每帧时间
    local frame = 0
    local skip

    local co

    function _M.start(_co)
        co = _co
    end

    function _M.update()
        frame = frame + 1
        timestamp = frame * frame_time
        _M.frame = frame
        _M.now = timestamp
    end

    function _M.set_multi(multi)
        local speed = cfg[multi][3] / 10
        granule = speed
    end

    function _M.pause(bctx, _pause)
        if skip then return end
        local o
        o, pause = pause, _pause
        _M.ispause = pause
        if _pause ~= true and o == true then bco.wakeup(bctx, co, 2) end
    end

    function _M.granule()
        if skip then return 0 end
        if combo_ti < timestop then return granule_init end
        return granule
    end

    function _M.set_skip()
        skip = true
    end

    return _M
end
