local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local objmgr = require "map.objmgr"
local umath = require "util.math"
local schema = require "mongo.schema"

local cache = require("map.cache")("mission")

local _M = {}

local FTARGET, MAP
skynet.init(function()
    FTARGET, MAP = cfgproxy("crack_ftarget", "crack_map")
end)

cache.schema(schema.SAR())

local INIT, SUM

_M.type = {monster_die = 1, chat = 2, box_open = 3}

function _M.finish(tp, label)
    if not INIT or not label then return end
    local subtbl = FTARGET[tp]
    if not subtbl then return end
    local id = subtbl[label]
    if not id then return end
    local cfg_map = MAP[INIT.mapkey]
    local target_dict = cfg_map.dict
    local cfg = target_dict[id]
    if not cfg then return end

    local C = cache.get()
    local cnt = C[id] or 0
    if cnt >= cfg[3] then return end

    cnt = cnt + 1
    C[id] = cnt
    cache.dirty()
    SUM = SUM + 1
    local progress = umath.round(SUM / cfg_map.total * 100)
    objmgr.agent_send(INIT.call, progress, id, cnt, cfg_map.mapid)
    objmgr.clientpush("map_target_finish",
        {progress = progress, target = {id = id, cnt = cnt}})
end

require("map.mods") {
    name = "target",
    init = function(ctx)
        INIT = ctx.target
    end,
    enter = function()
        if not INIT then return end
        local sum = 0
        local cfg_map = MAP[INIT.mapkey]
        local target_dict = cfg_map.dict
        local target = {}
        local push = {target = target}
        local C = cache.get()
        for _, id in ipairs(cfg_map.target) do
            local cfg = target_dict[id]
            local num = math.min(C[id] or 0, cfg[3])
            sum = sum + num
            table.insert(target, {id = id, cnt = num})
        end
        SUM = sum
        push.progress = umath.round(SUM / cfg_map.total * 100)
        objmgr.clientpush("map_target_info", push)
    end
}

return _M
