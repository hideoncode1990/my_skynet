local skynet = require "skynet"
local hinit = require "hero"
local client = require "client.mods"
local cfgproxy = require "cfg.proxy"
local words = require "words"
local event = require "role.event"
local roleinfo = require "roleinfo.change"
local flowlog = require "flowlog"
local hero = require "hero"
local hattrs = require "hero.attrs"
local cache = require("mongo.role")("characterinfo")
local noticecheck = require "util.noticecheck"

local _H = require "handler.client"
local _LUA = require "handler.lua"

local remove = table.remove
local insert = table.insert

local BASIC
skynet.init(function()
    BASIC = cfgproxy("basic")
end)

local NM<const> = "crainfo"
local CNT<const> = 5

require("role.mods") {
    name = NM,
    enter = function(self)
        local C = cache.get(self)
        client.enter(self, NM, "characterinfo", {
            mainforce = C.mainforce,
            zdl = self.zdl,
            signature = C.signature
        })
    end
}

local function signature_change(self, signature, flag)
    local e
    signature, e = noticecheck(signature, {0, BASIC.dec_limit})
    if not signature then return false, e end
    local C = cache.get(self)
    C.signature = signature
    cache.dirty(self)

    roleinfo.change(self, "signature", signature)
    flowlog.role_act(self, {flag = flag, arg1 = signature})
    return signature
end

function _H.characterinfo_signature(self, msg)
    local signature, e = signature_change(self, msg.signature,
        "characterinfo_signature")
    if not signature then return {e = e} end

    return {e = 0, signature = signature}
end

local function update_mainforce(self, mainforce)
    local ret = {}
    for _, uuid in ipairs(mainforce) do
        local info = {}
        local obj = hero.query(self, uuid)
        info.id = obj.id
        info.level = obj.level
        insert(ret, info)
    end
    roleinfo.change(self, "mainforce", ret)
end

function _H.characterinfo_mainforce_change(self, msg)
    local uuids = msg.uuids
    local C = cache.get(self)
    local mainforce = {}
    for i = 1, CNT do
        local uuid = uuids[i]
        if uuid then
            if not hinit.query(self, uuid) then
                return {e = 2}
            else
                insert(mainforce, uuid)
            end
        else
            break
        end
    end
    C.mainforce = mainforce
    cache.dirty(self)
    update_mainforce(self, mainforce)
    flowlog.role_act(self, {
        flag = "characterinfo_mainforce_change",
        arg1 = mainforce
    })
    return {e = 0}
end

function _LUA.mainfore_detail(self)
    local detail = {}
    local mainforce = cache.getsub(self, "mainforce")
    for k, uuid in ipairs(mainforce) do
        detail[k] = hattrs.pack(self, hero.query(self, uuid))
    end
    return detail
end

function _H.characterinfo_query(self, msg)
    local rid = msg.rid
    local info = roleinfo.query(rid, {"mainforce", "signature", "gid", "gname"})
    if not info then return {e = 2} end
    return {e = 0, info = info}
end

event.reg("EV_HERO_LVUP", NM, function(self, _uuid)
    local C = cache.get(self)
    local mainforce = C.mainforce
    if not mainforce or not next(mainforce) then return end
    for _, uuid in ipairs(mainforce) do
        if uuid == _uuid then
            update_mainforce(self, mainforce)
            return
        end
    end
end)

event.reg("EV_HERO_STAGEUP", NM, function(self, uuid2id)
    local C = cache.get(self)
    local mainforce = C.mainforce
    if not mainforce or not next(mainforce) then return end
    for uuid in pairs(uuid2id) do
        for _, _uuid in ipairs(mainforce) do
            if _uuid == uuid then
                update_mainforce(self, mainforce)
                return
            end
        end
    end
end)

event.reg("EV_HERO_DELS", NM, function(self, uuids)
    local C = cache.get(self)
    local mainforce = C.mainforce
    if not mainforce or not next(mainforce) then return end
    local change
    for _, uuid in ipairs(uuids) do
        for i, _uuid in ipairs(mainforce) do
            if _uuid == uuid then
                remove(mainforce, i)
                change = true
                break
            end
        end
    end

    if change then
        cache.dirty(self)
        update_mainforce(self, mainforce)
    end
end)
