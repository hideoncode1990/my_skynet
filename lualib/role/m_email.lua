local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local queue = require "skynet.queue"
local client = require "client.mods"
local award = require "role.award"
local utime = require "util.time"
local uaward = require "util.award"
local utable = require "util.table"
local logerr = require "log.err"
local dbhelper = require "email.dbhelper"
local cache = require("mongo.role")("email")

local _LUA = require "handler.lua"
local _H = require "handler.client"
local LOCK = queue()

local EMAIL_CACHE = {}
local NM<const> = "email"

local emailwatcher
local BASIC
skynet.init(function()
    BASIC = cfgproxy("basic")
    emailwatcher = skynet.uniqueservice "game/emailwatcher"
end)

local function rolecache_execute(self)
    local C = cache.get(self)
    local read = C.read
    local dirty
    if next(read) then
        C.read = {}
        dirty = true
    end
    local proxy = self.proxy
    for eid, ti in pairs(read) do dbhelper.read(proxy, eid, ti) end
    if dirty then cache.dirty(self) end

    dirty = nil
    local delete = C.delete
    if next(delete) then
        C.delete = {}
        dirty = true
    end
    for eid in pairs(delete) do dbhelper.delete(proxy, eid) end
    if dirty then cache.dirty(self) end
end

local rolecache_insave
local function rolecache_check(self)
    if rolecache_insave then return end
    rolecache_insave = true
    skynet.fork(function()
        skynet.sleep(100)
        local ok, err = xpcall(rolecache_execute, debug.traceback, self)
        if not ok then logerr(err) end
        rolecache_insave = nil
    end)
end

local function email_pack(e)
    local items = e.items
    if items then
        local ne = utable.copy(e)
        ne.items = uaward.pack(items)
        return ne
    else
        return e
    end
end

local function email_delete_inner(self, C, eid, now)
    EMAIL_CACHE[eid] = nil
    C.delete[tostring(eid)] = now or utime.time()
    rolecache_check(self)
end

local function email_refresh(self, nlist)
    local now = utime.time()
    local C = cache.get(self)
    local ECACHE = EMAIL_CACHE

    for _, e in ipairs(nlist or {}) do ECACHE[e.id] = e end

    for eid, ti in pairs(C.read) do
        local e = ECACHE[tonumber(eid)]
        if e then e.readtime = ti end
    end
    for eid in pairs(C.delete) do ECACHE[tonumber(eid)] = nil end

    local list, dels = {}, {}
    local email_maxtime = BASIC.email_maxtime
    for eid, e in pairs(ECACHE) do
        local deltime = e.deltime
        if not deltime then
            deltime = e.time + email_maxtime
            e.deltime = deltime
        end
        if now >= deltime then
            table.insert(dels, eid)
        else
            table.insert(list, eid)
        end
    end

    table.sort(list, function(a, b)
        return ECACHE[a].time > ECACHE[b].time
    end)
    for i = BASIC.email_maxcnt + 1, #list do table.insert(dels, list[i]) end

    for _, eid in ipairs(dels) do email_delete_inner(self, C, eid) end
    return dels, list
end

local function email_all(self)
    local list = dbhelper.findall(self.proxy, {target = self.rid})
    email_refresh(self, list)
end

local function email_grab(self, C, eid, now, nodel)
    local e = EMAIL_CACHE[eid]
    if e then
        if e.deltime > (now or utime.time()) then
            return e
        else
            if not nodel then email_delete_inner(self, C, eid) end
        end
    end
end

local function email_foreach(self, C, cb)
    local now = utime.time()
    local dels = {}
    for eid in pairs(EMAIL_CACHE) do
        local e = email_grab(self, C, eid, now, true)
        if e then
            cb(e, eid)
        else
            table.insert(dels, eid)
        end
    end
    for _, eid in ipairs(dels) do email_delete_inner(self, C, eid) end
end

require("role.mods") {
    name = NM,
    load = function(self)
        local C = cache.get(self)
        if not C.read then
            C.read = {}
            cache.dirty(self)
        end
        if not C.delete then
            C.delete = {}
            cache.dirty(self)
        end
    end,
    loadafter = function(self)
        skynet.call(emailwatcher, "lua", "reg", self.rid, skynet.self())
        LOCK(email_all, self)
    end,
    enter = function(self)
        local C = cache.get(self)
        local list = {}
        email_foreach(self, C, function(e, eid)
            list[eid] = email_pack(e)
        end)
        client.enter(self, NM, "email_all", {list = list})
    end,
    unload = function(self)
        rolecache_execute(self)
        skynet.call(emailwatcher, "lua", "unreg", self.rid)
    end
}

function _LUA.email_receive(self, eid)
    local e = dbhelper.findone(self.proxy, {id = eid})
    assert(e.target == self.rid)
    local dels = LOCK(email_refresh, self, {e}) -- ensure call it after loaded.email_all
    if #dels > 0 then client.push(self, NM, "email_del", {list = dels}) end
    client.push(self, NM, "email_new", {email = email_pack(e)})
end

function _H.emailread(self, msg)
    local C = cache.get(self)
    local eid = msg.id
    local e = email_grab(self, C, eid)
    if not e then return {e = 1} end
    if e.readtime > 0 then return {e = 2} end
    local readtime = utime.time()

    local items = e.items
    if items then
        local ok, err = award.checkadd(self, items)
        if not ok then return {e = err} end
    end

    e.readtime = readtime
    C.read[tostring(eid)] = readtime
    rolecache_check(self)

    if items then assert(award.add(self, e.option, items)) end
    return {
        e = 0,
        readtime = readtime,
        items = items and uaward.pack(items) or {}
    }
end

function _H.emailread_all(self)
    local C = cache.get(self)
    local list = {}
    email_foreach(self, C, function(e, eid)
        if e.readtime == 0 and e.items then table.insert(list, eid) end
    end)
    local now = utime.time()
    local ret = {}
    local the_items = uaward()
    for _, eid in ipairs(list) do
        local e = EMAIL_CACHE[eid]
        local items = e.items

        local ok = award.checkadd(self, items)
        if ok then
            assert(e.readtime == 0)

            e.readtime = now
            C.read[tostring(eid)] = now
            rolecache_check(self)

            table.insert(ret, eid)
            assert(award.add(self, e.option, items))
            the_items.append(items)
        end
    end
    return {e = 0, list = ret, readtime = now, items = the_items.pack()}
end

function _H.emaildelete(self, msg, force)
    local C = cache.get(self)
    local eid = msg.id
    local e = EMAIL_CACHE[eid]

    if not e then return {e = 1} end
    if not force and e.readtime == 0 then return {e = 2} end

    email_delete_inner(self, C, eid)
    return {e = 0}
end

function _H.emaildelete_all(self, _, force)
    local C = cache.get(self)

    local list = {}
    email_foreach(self, C, function(e, eid)
        if force or e.readtime > 0 then table.insert(list, eid) end
    end)

    local now = utime.time()
    local ret = {}
    for _, eid in ipairs(list) do
        local e = EMAIL_CACHE[eid]
        if not force then assert(e.readtime > 0) end

        email_delete_inner(self, C, eid, now)
        table.insert(ret, eid)
    end
    return {e = 0, list = ret}
end
