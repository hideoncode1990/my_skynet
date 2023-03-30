local attrlib = require "util.attrs"
local attrkeys = attrlib.keys
local attrpara = attrlib.para
local uplimit = attrlib.uplimit
local minlimit = attrlib.minlimit
local ucopy = require"util.table".copy
local floor = math.floor
local min = math.min
local max = math.max
local getsub = require"util.table".getsub

local _M = {}

local function hp_back(self, prior_hpmax)
    local hp = self.attrs.hp
    local hpmax = self.attrs.hpmax
    if hpmax > prior_hpmax then
        self.attrs.hp = floor((hp / prior_hpmax) * hpmax)
    end
end

local function trigger_hpmax_change(self, attrs)
    if not attrs then attrs = self.attrs end
    local hp = attrs.hp
    local hpmax = attrs.hpmax
    if hp >= hpmax then attrs.hp = hpmax end
end

local function set_attrs(self, as, lasthp, lasttpv)
    local attrs = self.attrs
    local attrs_b = self.attrs_b
    for key in pairs(attrkeys) do
        attrs_b[key] = as[key] or 0
        rawset(attrs, key, nil)
    end
    if lasthp then rawset(attrs, "hp", lasthp) end
    if lasttpv then rawset(attrs, "tpv", lasttpv) end
end

function _M.init(self)
    local attrs_b = {}
    local attrs_a = self.attrs_a or {}
    local attrs_p = self.attrs_p or {}
    local attrs_a_ex, attrs_p_ex = {}, {}
    local attrs = setmetatable({}, {
        __index = function(t, k)
            local v = ((attrs_b[k] or 0) + (attrs_a[k] or 0) +
                          (attrs_a_ex[k] or 0)) *
                          (1 + ((attrs_p[k] or 0) + (attrs_p_ex[k] or 0)) / 1000)
            if uplimit[k] then v = min(uplimit[k], v) end
            if minlimit[k] then v = max(minlimit[k], v) end
            v = floor(v)
            if k == "speed" then
                local v1, v2 = t["rapid"] / attrpara.rapid,
                    t["speed_add"] / attrpara.speed_add
                v = v * (1 + v1 + v2)
                v = floor(max(0, v))
            elseif k == "atkspeed" then
                v = 1 + v / attrpara.atkspeed + t["rapid"] / attrpara.rapid
                v = max(0.01, v)
            end
            rawset(t, k, v)
            return v
        end,
        __newindex = function()
            error("unsupport")
        end
    })
    self.attrs = attrs
    self.attrs_b = attrs_b
    self.attrs_a = attrs_a
    self.attrs_p = attrs_p
    self.attrs_a_ex = attrs_a_ex
    self.attrs_p_ex = attrs_p_ex
    self.attrs_ex_m = {a = {}, p = {}}

    local baseattrs = self.baseattrs
    local lasthp = self.lasthp or baseattrs.hpmax
    local lasttpv = self.lasttpv or 0
    set_attrs(self, baseattrs, lasthp, lasttpv)
    trigger_hpmax_change(self, attrs)
end

local function attr_special(self, key, prior)
    local attrs = self.attrs
    if key == "hpmax" then
        hp_back(self, prior)
        trigger_hpmax_change(self, attrs)
    end
    if key == "rapid" then
        rawset(attrs, "speed", nil)
        rawset(attrs, "atkspeed", nil)
    elseif key == "speed_add" then
        rawset(attrs, "speed", nil)
    end
end

function _M.add_a(self, key, val)
    local attrs = self.attrs
    local a = self.attrs_a[key] or 0
    self.attrs_a[key] = (val or 0) + a
    local prior = attrs[key]
    rawset(attrs, key, nil)
    attr_special(self, key, prior)
end

function _M.add_p(self, key, val)
    local attrs = self.attrs
    local p = self.attrs_p[key] or 0
    self.attrs_p[key] = (val or 0) + p
    local prior = attrs[key]
    rawset(attrs, key, nil)
    attr_special(self, key, prior)
end

function _M.set_a_ex(self, key, val, m)
    local attrs = self.attrs
    local as = getsub(self.attrs_ex_m.a, m)
    local a = as[key] or 0
    if a ~= val then
        as[key] = val
        self.attrs_a_ex[key] = (self.attrs_a_ex[key] or 0) + (val - a)
        local prior = attrs[key]
        rawset(attrs, key, nil)
        attr_special(self, key, prior)
    end
end

function _M.set_p_ex(self, key, val, m)
    local attrs = self.attrs
    local as = getsub(self.attrs_ex_m.p, m)
    local a = as[key] or 0
    if a ~= val then
        self.attrs_p_ex[key] = (self.attrs_p_ex[key] or 0) + (val - a)
        local prior = attrs[key]
        rawset(attrs, key, nil)
        attr_special(self, key, prior)
    end
end

function _M.reset(self, key)
    self.attrs_a[key] = nil
    self.attrs_p[key] = nil
    rawset(self.attrs, key, nil)
end

function _M.copy_base(self, coes)
    coes = coes or {}
    local baseattrs = {}
    local attrs_b = self.attrs_b
    for key in pairs(attrkeys) do
        local coe = (coes[key] or 1000) / 1000
        baseattrs[key] = floor(attrs_b[key] * coe)
    end
    return baseattrs
end

function _M.copy(self, tobj, coes)
    coes = coes or {}
    local baseattrs = {}
    local attrs_b = tobj.attrs_b
    for key in pairs(attrkeys) do
        local coe = (coes[key] or 1000) / 1000
        baseattrs[key] = floor(attrs_b[key] * coe)
    end
    self.baseattrs = baseattrs
    self.attrs_a = ucopy(tobj.attrs_a)
    self.attrs_p = ucopy(tobj.attrs_p)
end

function _M.check_show(key)
    if key == "hpmax" or key == "rapid" or key == "speed" or key == "speed_add" or
        key == "atkspeed" or key == "tpvmax" then return true end
end

require "battle.mods"("attrcalc", _M)
return _M
