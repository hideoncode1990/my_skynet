local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local client = require "client"
local cache = require("mongo.role")("citytalent")
local getupvalue = require "debug.getupvalue"

local _MAS = require "handler.master"

local ondirty = getupvalue(require("handler.client").citytalent_levelup,
    "ondirty")

local CFG
skynet.init(function()
    CFG = cfgproxy "citytalent"
end)

function _MAS.citytalent_list(self)
    local C = cache.get(self)
    local list = {}
    for id, cfg in pairs(CFG) do
        table.insert(list, {
            id = id,
            name = cfg.name,
            level = C[id] or 0,
            type = cfg.type
        })
    end
    return {e = 0, list = list}
end

function _MAS.citytalent_change(self, ctx)
    local query = ctx.query
    local id, level = tonumber(query.id), tonumber(query.level)
    local cfgs = CFG[id]
    if not cfgs then return {e = -1, m = "id error"} end

    local cfg = cfgs[level]
    if not cfg then return {e = -1, m = "level error"} end
    local C = cache.get(self)
    C[id] = level
    cache.dirty(self)
    ondirty(self)
    client.push(self, "citytalent_info", {list = C})
    return {e = 0}
end
