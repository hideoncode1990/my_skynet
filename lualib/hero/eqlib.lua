local skynet = require "skynet"
local generate = require "role.award.generate"
local uattrs = require "util.attrs"
local cfgproxy = require "cfg.proxy"
local uniq = require "uniq.c"
local _M = {}

local MODS, CFG = {}, nil

skynet.init(function()
    CFG = cfgproxy("equip")
end)

function _M.reg(nm, cb)
    MODS[nm] = cb
end

-- total=base*coe
local function calc_attrs(self, eqdata)
    local coe_sum = 1000
    for _, cb in pairs(MODS) do
        local coe = cb(self, eqdata)
        coe_sum = coe_sum + (coe or 0)
    end
    local base = uattrs.filter(CFG[eqdata.id])
    return uattrs.append_coe(base, coe_sum)
end

function _M.load_other(self, eqdata)
    local attrs = calc_attrs(self, eqdata)
    eqdata.attrs = attrs
    eqdata.zdl = uattrs.zdl(attrs)
end

function _M.create_equip(_, id, _feature)
    local feature
    if _feature == nil then
        feature = generate.feature(id)
    else
        feature = _feature > 0 and _feature or nil
    end
    return {uuid = uniq.uuid(), id = id, feature = feature, level = 0, exp = 0}
end

function _M.recreate_feature(_, id, oldfeature)
    return generate.re_feature(id, oldfeature)
end

_M.calc_attrs = calc_attrs

return _M
