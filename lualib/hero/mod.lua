local logerr = require "log.err"
local hattrs = require "hero.attrs"

local traceback = debug.traceback
local insert = table.insert
local xpcall = xpcall

local _M = {}

local MODS = {}

function _M.reg(m)
    local name = m.name
    assert(name)
    for _, mod in ipairs(MODS) do
        if mod.name == name then
            error("dumplicate hero module: " .. name)
        end
    end
    insert(MODS, m)
end

local function callfield(name, ...)
    for _, v in ipairs(MODS) do
        local call = v[name]
        if call then
            local ok, err = xpcall(call, traceback, ...)
            if not ok then logerr(err) end
        end
    end
end

local function revert_callfield(name, ...)
    for i = #MODS, 1, -1 do
        local call = MODS[i][name]
        if call then
            local ok, err = xpcall(call, traceback, ...)
            if not ok then logerr(err) end
        end
    end
end

function _M.init(self, uuid, obj)
    callfield('init', self, uuid, obj)
end

function _M.load(self)
    callfield('load', self)
end

function _M.loaded(self)
    callfield('loaded', self)
end

-- function _M.loadafter(self)
--     callfield('loadafter', self)
-- end

function _M.enter(self)
    callfield('enter', self)
end

-- function _M.leave(self)
--     revert_callfield('leave', self)
-- end

-- function _M.afk(self)
--     revert_callfield('afk', self)
-- end

-- function _M.unload(self)
--     revert_callfield('unload', self)
-- end

function _M.create(self, uuid, obj)
    callfield('create', self, uuid, obj)
end

function _M.levelup(self, uuid, obj)
    callfield('levelup', self, uuid, obj)
end

function _M.inherit(self, uuid, obj)
    callfield('inherit', self, uuid, obj)
end

function _M.reset(self, uuid, obj, option)
    revert_callfield('reset', self, uuid, obj, option)
    return obj
end

function _M.remove(self, uuid, obj, option)
    revert_callfield('remove', self, uuid, obj, option)
    return obj
end

return _M

