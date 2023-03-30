local cache = require "mongo.role"
local logerr = require "log.err"
local MODS = {}

local error = error
local ipairs = ipairs
local traceback = debug.traceback
local xpcall = xpcall

local function call(n, ...)
    for _, mod in ipairs(MODS) do
        local func = mod[1][n]
        if func then
            local ok, err = xpcall(func, traceback, ...)
            if not ok then logerr(err) end
        end
    end
end

local function reg(m, name)
    name = name or m.name
    assert(name and m)
    for _, mod in ipairs(MODS) do
        if mod[2] == name then error("dumplicate module " .. name) end
    end
    if name then table.insert(MODS, {m, name}) end
end

local _M = {}

function _M.init(self)
    call("init", self)
end

function _M.new(self)
    call("new", self)
end
function _M.load(self)
    call("load", self)
end

function _M.loaded(self)
    call("loaded", self)
end

function _M.enter(self)
    call("enter", self)
end
function _M.get(_, nm)
    for _, mod in ipairs(MODS) do if mod[2] == nm then return mod[1] end end
end

setmetatable(_M, {
    __call = function(_, n, m)
        reg(n, m)
    end
})

return _M
