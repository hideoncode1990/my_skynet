local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local client = require "client.mods"
local condition = require "role.condition"
local utime = require "util.time"
local event = require "role.event"
local ctype = require "role.condition.type"
local cache = require("mongo.role")("fnopens")
local logerr = require "log.err"
local schema = require "mongo.schema"
local cfgbase = require "cfg.base"

local xpcall = xpcall
local table = table
local ipairs = ipairs
local traceback = debug.traceback
local assert = assert
local tostring = tostring

local NM<const> = "fnopen"

local _M = {}

local CFG
skynet.init(function()
    CFG = cfgproxy("fnopen")
end)

cache.schema(schema.SAR())

local events = {}
function _M.reg(nm, mod, cb)
    assert(CFG.fnopen[nm] and mod and cb)
    local grp = events[nm]
    if not grp then
        grp = {}
        events[nm] = grp
    end
    for _, node in ipairs(grp) do
        if node[2] == mod then
            node[1], mod = cb, nil
            logerr("duplicated call in cb %s.%s", tostring(nm),
                tostring(node[2]))
            break
        end
    end
    if mod then table.insert(grp, {cb, mod}) end
end

local function occur(self, nm, id, ...)
    local grp = events[nm]
    if grp then
        for _, node in ipairs(grp) do
            local ok, err = xpcall(node[1], traceback, self, nm, id, ...)
            if not ok then logerr(err) end
        end
    end
end

local function do_checkid(self, id, cfg, C)
    if C[id] then return true end
    local r = condition.check(self, cfg.precondition)
    if r then
        if C[id] then return true end
        C[id] = utime.time_int()
        cache.dirty(self)
        skynet.fork(occur, self, cfg.mark, id)
        return true, id
    else
        return false
    end
end

-- state : 1 已开启
local function do_check(self, nm, C)
    local cfg = assert(CFG.fnopen[nm], nm)
    return do_checkid(self, cfg.id, cfg, C)
end

local function do_checkandsend(self, nm, C, _) -- 第四个参数是ref, 保留这个参数是为了让它的生命周期保留到这个函数结束
    local _, id = do_check(self, nm, C)
    if id then client.push(self, NM, "fnopen_new", {ids = {id}}) end
end

local inchecked = setmetatable({}, {__mode = "v"}) -- 限制try_check触发次数
local function try_check(self, id, cfg, C)
    if inchecked[id] then return end
    local ref = {}
    inchecked[id] = ref
    skynet.fork(do_checkandsend, self, id, C, ref)
end

function _M.check_open(self, nm)
    local C = cache.get(self)
    local cfg = assert(CFG.fnopen[nm])
    local id = cfg.id
    if C[id] then return true end
    try_check(self, id, cfg, C) -- check_open任然会触发检测
end

local function trigger(self, rets, tp, C)
    local ids = CFG.tp_ids[tp]
    if not ids then return end
    for id in pairs(ids) do
        if not C[id] then
            local _, nid = do_check(self, id, C)
            if nid then table.insert(rets, nid) end
        end
    end
end

local function fnopen_trigger(self, tp)
    local rets = {}
    trigger(self, rets, tp, cache.get(self))
    if next(rets) then client.push(self, NM, "fnopen_new", {ids = rets}) end
end

local function trigger_all(self)
    local C = cache.get(self)
    for _, id in pairs(CFG.all_ids) do
        if not C[id] then do_check(self, id, C) end
    end
end

local done
local function init(self)
    if done then return end
    done = true
    trigger_all(self)
end

local function push(self)
    local msg = {}
    for id in pairs(cache.get(self)) do table.insert(msg, id) end
    if #msg > 0 then client.enter(self, NM, "fnopen_list", {ids = msg}) end
end

require("role.mods") {
    name = NM,
    load = function(self)
        cfgbase.onchange(function()
            trigger_all(self)
        end, "fnopen")
    end,
    enter = function(self)
        init(self)
        push(self)
    end
}

event.reg("EV_LVUP", NM, function(self)
    fnopen_trigger(self, ctype.role_level)
end)

event.reg("EV_MAINLINE", NM, function(self)
    fnopen_trigger(self, ctype.mainline)
end)

event.reg("EV_HERO_LVREAL_UP", NM, function(self)
    fnopen_trigger(self, ctype.hero_level)
end)

local working
event.reg("EV_HERO_STAGEUP", NM, function(self)
    if not working then
        working = true
        skynet.fork(function()
            skynet.sleep(100)
            working = nil
            fnopen_trigger(self, ctype.hero_stage_cnt)
        end)
    end
end)

event.reg("EV_VIP_LVUP", NM, function(self)
    fnopen_trigger(self, ctype.vip)
end)

return _M
