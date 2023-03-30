local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local objmgr = require "map.objmgr"
local mode = require "map.fight_mode"
local cache = require("map.cache")("supply")

local BASIC, OPEN
skynet.init(function()
    BASIC = cfgproxy("basic")
end)

local function get_val()
    local C = cache.get()
    if not C.val then
        C.val = BASIC.crack_limit_supply or 100
        cache.dirty()
    end
    return C, C.val
end

require("map.mods") {
    name = "supply",
    init = function(ctx)
        if ctx.fight_mode == mode.supply then OPEN = true end
    end,
    enter = function()
        if not OPEN then return end
        print("map_supply_value", get_val().val)
        objmgr.clientpush("map_supply_value", get_val())
    end
}

local _M = {}

function _M.add(addval)
    if not OPEN then return end
    assert(addval > 0)
    local C, val = get_val()
    C.val = math.min(BASIC.crack_limit_supply, val + addval)
    cache.dirty()
    objmgr.clientpush("map_supply_value", C)
    print("map_supply_value", get_val().val)
end

function _M.check()
    if not OPEN then return true end
    local _, val = get_val()
    return val > 0
end

function _M.del(delval)
    if not OPEN then return end
    assert(delval > 0)
    local C, val = get_val()
    C.val = math.max(val - delval, 0)
    cache.dirty()
    objmgr.clientpush("map_supply_value", C)
    print("map_supply_value", get_val().val)
    return C.val > 0
end

function _M.get()
    local _, val = get_val()
    return val, BASIC.crack_limit_supply
end

return _M
