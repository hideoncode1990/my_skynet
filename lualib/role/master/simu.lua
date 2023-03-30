local skynet = require "skynet"
local _MAS = require "handler.master"
local simu = require "role.m_simulation"
local getupvalue = require "debug.getupvalue"
local cfgdata = require "cfg.data"

function _MAS.simu(self, ctx)
    local feature = tonumber(ctx.query.feature)
    local floor = tonumber(ctx.query.floor)
    local ok, err = simu.simu(self, feature, floor)
    if not ok then return {e = 1, m = err} end
    return {e = 0}
end

function _MAS.simu_info(self)
    local cache = getupvalue(simu.simu, "cache")
    local data = cache.getsub(self, "floor")
    local info = {}
    for feature in pairs(cfgdata.simulation) do
        table.insert(info, {feature = feature, floor = data[feature] or 0})
    end
    return {e = 0, info = info}
end
