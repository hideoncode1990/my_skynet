local skynet = require "skynet"
local cfgdata = require "cfg.data"
local umath = require "util.math"

local ids, keys, para, zdl_para, types, marks = {}, {}, {}, {}, {}, {}
local uplimit, minlimit = {}, {}

local special_attrs = {
    ["hpmax"] = "hpmax_perc",
    ["atk"] = "atk_perc",
    ["def"] = "def_perc"
}

local special_attrs2 = {}

skynet.init(function()
    for id, cfg in pairs(cfgdata.attribute) do
        local nm = cfg.name or id
        ids[id] = nm
        keys[nm] = id
        para[id], para[nm] = cfg.para, cfg.para
        zdl_para[id], zdl_para[nm] = cfg.zdl, cfg.zdl
        uplimit[nm] = cfg.uplimit
        minlimit[nm] = cfg.minlimit
        types[id] = cfg.type
        if cfg.mark then
            marks[id] = true
            marks[nm] = true
        end
    end
    for k, v in pairs(special_attrs) do special_attrs2[keys[k]] = keys[v] end
end)

local _M = {}

_M.ids = ids
_M.keys = keys
_M.para = para
_M.uplimit = uplimit
_M.minlimit = minlimit

function _M.is_type(id, nm)
    return types[id] == nm
end

--[[
血量(总) = 血量(基础) * coe * (1 + 加成) + 血量(其他)
血量(总)= 血量(基础) * (coe * (1 + 加成)) - 血量(基础) + 血量(基础) + 血量(其他)
血量(总)= 血量(基础) * (coe * (1 + 加成) - 1) + 血量(基础) + 血量(其他)
]]
function _M.hero_attrs(attrs, baseattr, coe)
    for k, v in pairs(special_attrs2) do
        local perc = (attrs[v] or 0) / para[v]
        attrs[k] = umath.round(attrs[k] + (baseattr[k] or 0) *
                                   (coe * (1 + perc) - 1))
    end
    return attrs
end

function _M.append(ret, attrs)
    for k, v in pairs(attrs) do ret[k] = (ret[k] or 0) + v end
    return ret
end

function _M.append_coe(attrs, coe)
    assert(coe > 0)
    local ret = {}
    for k, v in pairs(attrs) do ret[k] = umath.round(v * coe / 1000) end
    return ret
end

function _M.multi_coes(attrs, coes)
    local ret = {}
    for k, v in pairs(attrs) do
        local coe = coes[k] or 1000
        ret[k] = umath.round(v * coe / 1000)
    end
    return ret
end

function _M.for_fight(attrs)
    local ret = {}
    for id, v in pairs(attrs) do ret[ids[id]] = v end
    return ret
end

function _M.append_array(ret, attrs)
    for _, info in ipairs(attrs) do
        local k, v = info[1], info[2]
        ret[k] = (ret[k] or 0) + v
    end
end

-- function _M.with_para(attrs)
--     for k, v in pairs(attrs) do
--         if para[k] then
--             local val = v / para[k]
--             attrs[k] = val
--         end
--     end
--     return attrs
-- end

function _M.compare(new, old)
    local dict, marks = {}, {}
    for k, v in pairs(new) do
        local rv = old[k] or 0
        if rv ~= v then dict[k] = v end
        marks[k] = true
    end
    for k in pairs(old) do if not marks[k] then dict[k] = 0 end end
    return dict
end

function _M.filter(attrs)
    local ret = {}
    for nm, val in pairs(attrs) do
        local id = keys[nm]
        if id then ret[id] = val end
    end
    return ret
end

function _M.zdl(attrs)
    local zdl = 0
    for id, val in pairs(attrs) do zdl = zdl + val * (zdl_para[id] or 0) end
    return umath.round(zdl)
end

function _M.zdl_noround(attrs)
    local zdl = 0
    for id, val in pairs(attrs) do zdl = zdl + val * (zdl_para[id] or 0) end
    return zdl
end

function _M.pack(attrs)
    local ret = {}
    for id, val in pairs(attrs) do if marks[id] then ret[id] = val end end
    return ret
end

return _M
