local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local utime = require "util.time"
local utable = require "util.table"
local schema = require "mongo.schema"
local cache = require("map.cache")("trigger")
local env = require "env"

cache.schema(schema.OBJ {triggers = schema.SAR(), watchers = schema.SET()})

local _M = {}

local CFG, INITCALL, TRIGGERS
local CLASS = {}
local WATCHER = setmetatable({}, {
    __index = function(t, k)
        local v = {}
        t[k] = v
        return v
    end
})

require("map.mods") {
    name = "trigger",
    init = function(ctx)
        local method = {}
        for file in require("lfs").dir(env.root .. "/lualib/map/trigger") do
            if file ~= "." and file ~= ".." then
                local pos = string.find(file, ".lua$")
                if pos then
                    local ttype = string.sub(file, 1, pos - 1)
                    local init = require("map.trigger." .. ttype)(ttype)
                    if type(init) == "function" then
                        method[ttype] = function(cfg)
                            init(cfg)
                        end
                    end
                end
            end
        end
        CFG = cfgproxy("exploremap")[ctx.mapid]
        INITCALL = method
    end,
    load = function()
        local C = cache.get()
        TRIGGERS = C.triggers
        for _, ctx in pairs(TRIGGERS or {}) do
            if ctx ~= true then _M.load_trigger(ctx) end
        end
        for id in pairs(C.watchers or {}) do
            local cfg = CFG[id]
            INITCALL[cfg.type](cfg)
        end
        for id, cfg in pairs(CFG) do
            if not TRIGGERS[id] then
                local init = INITCALL[cfg.type]
                if init then init(cfg) end
            end
        end
    end,
    loaded = function()
        _M.invoke("load")
    end
}

--- @param type string trigger type
--- @param class table trigger class
function _M.reg(type, class)
    CLASS[type] = class
end

--- 开起事件
--- @param id number trigger id
--- @return boolean
function _M.start(id)
    if TRIGGERS[id] then return true end
    local cfg = CFG[id]
    local condition = cfg.condition
    if condition and not utable.logic(TRIGGERS, condition) then return false end

    local type = cfg.type
    local class = CLASS[type]
    local ctx = {id = id, type = type, ti = utime.time_int()}
    TRIGGERS[id] = ctx
    local load, start = class.load, class.start
    if load then load(ctx, cfg) end

    start(ctx, cfg)
    cache.dirty()
    return true
end

function _M.load_trigger(ctx)
    local id = ctx.id
    local cfg = CFG[id]
    local type = cfg.type
    local class = CLASS[type]
    TRIGGERS[id] = ctx
    local start = class.start
    start(ctx, cfg)
end

--- 结束事件
--- @param id number trigger id
function _M.finish(id)
    local ctx = TRIGGERS[id]
    local cfg = CFG[id]
    _M.finishctx(ctx, cfg)
end

--- 结束事件
--- @param ctx table trigger ctx
--- @param cfg table|nil trigger cfg
function _M.finishctx(ctx, cfg)
    if ctx == true then return end
    local id = ctx.id
    cfg = cfg or CFG[id]
    TRIGGERS[id] = true
    cache.dirty()

    for _, nid in ipairs(cfg.nexts or {}) do skynet.fork(_M.start, nid, ctx) end
end

function _M.checkfinish(id)
    return TRIGGERS[id] == true
end

--- 根据事件类型监听invoke
--- @param id integer
--- @param call function(...):bool|nil
function _M.watch(id, call)
    local cfg = CFG[id]
    local type = cfg.type
    local watchers = WATCHER[type]
    watchers[id] = call
    local d = cache.getsub("watchers")
    if not d[id] then
        d[id] = true
        cache.dirty()
    end
end

--- 唤醒事件监听, 事件处理器返回成功就移除该事件处理器
--- @param type string trigger type
--- @vararg ...

function _M.invoke(type, ...)
    local watchers = WATCHER[type]
    local d = cache.getsub("watchers")
    for id, call in pairs(watchers or {}) do
        skynet.fork(function(...)
            if watchers[id] and call(...) then
                watchers[id] = nil
                d[id] = nil
                cache.dirty()
            end
        end, ...)
    end
end

--- @param id number trigger id
--- @return table trigger cfg
function _M.grabcfg(id)
    local cfg = CFG[id]
    return cfg
end

return _M
