local utable = require "util.table"
local skynet = require "skynet"
local mods = require "role.mods"
local getupvalue = require "debug.getupvalue"
local baseinfo = require "role.baseinfo"
local mainline = require "role.m_mainline"
local cfgproxy = require "cfg.proxy"
local award = require "role.award"
local awardtype = require "role.award.type"

local _MAS = require "handler.master"

local CFGVIP
require("skynet").init(function()
    CFGVIP = cfgproxy("vip")
end)

local function vip(self)
    local cache = getupvalue(mods.get(self, "vip").enter, "cache")
    local C = cache.get(self)
    local level, exp = C.level, C.exp
    return string.format("%d(%d/%d)", level, exp, CFGVIP[level].exp)
end

local function signature(self)
    local cache = getupvalue(mods.get(self, "crainfo").enter, "cache")
    local C = cache.get(self)
    return C.signature or ""
end

local function diamond(self)
    local cache = getupvalue(mods.get(self, "diamond").enter, "cache")
    local C = cache.get(self)
    local bind, bindcoin = C.bind, C.bindcoin
    return bind + bindcoin, bind, bindcoin
end

function _MAS.role_info(self)
    local ret = utable.copy(self)

    ret.mainline = self.mainline
    ret.zdl = self.zdl
    ret.level, ret.exp = baseinfo.levelget(self)

    ret.signature = signature(self)
    ret.vip = vip(self)
    ret.diamond = string.format("%d(%d+%d)", diamond(self))
    return {e = 0, data = ret}
end

local change = {}

function _MAS.role_change(self, ctx)
    local type, value = ctx.body.type, ctx.body.value
    return change[type](self, value)
end

function change.diamond(self, value)
    local val = tonumber(value)
    assert(val >= 0)
    local valnow = diamond(self)
    if valnow > val then
        assert(award.del(self, {flag = "MASTER_CHANGE"},
            {{awardtype.diamond, 0, valnow - val}}))
    elseif valnow < val then
        assert(award.add(self, {flag = "MASTER_CHANGE"},
            {{awardtype.diamond, 0, val - valnow}}))
    end
    return {e = 0}
end

function change.mainline(self, value)
    local ok = mainline.change(self, tonumber(value), {flag = "MASTER"})
    if not ok then return {e = 1} end
    mods.get(self, "mainline").enter(self)
    return {e = 0}
end

function change.rname(self, value)
    local func = require("handler.client").name_change
    local name_change = getupvalue(func, "name_change")
    local _, e = name_change(self, value, "changename_master")
    local m = {[4] = "namecheck failed", [7] = "no change"}

    return {e = e, m = m[e] or e}
end

function change.signature(self, value)
    local func = require("handler.client").characterinfo_signature
    local signature_change = getupvalue(func, "signature_change")
    local ok, e = signature_change(self, value, "signature_master")

    local m = {[1] = "too shot", [2] = "too long", [3] = "dirtycheck failed"}
    if not ok then return {e = e, m = m[e] or e} end

    mods.get(self, "crainfo").enter(self)
    return {e = 0}
end
