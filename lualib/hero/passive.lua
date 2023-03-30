local queue = require "skynet.queue"
local utable = require "util.table"
local timer = require "timer"

local LOCK = queue()
local insert = table.insert

local _M = {}

local CALL, CACHE = {}, {}
local indirty = {}

function _M.reg(nm, cb)
    assert(not CALL[nm])
    CALL[nm] = cb
end

local function get(_, uuid)
    return utable.sub(CACHE, uuid)
end

local function dirty_inner(self)
    local dirtys
    dirtys, indirty = indirty, {}
    for uuid, nmtab in pairs(dirtys) do
        local subtab = get(self, uuid)
        for nm in pairs(nmtab) do subtab[nm] = CALL[nm](self, uuid) end
    end
end

function _M.init(self, uuid)
    local subtab = get(self, uuid)
    for nm, cb in pairs(CALL) do subtab[nm] = cb(self, uuid) end
end

function _M.dirty(self, nm, ...)
    if not next(indirty) then
        timer.add(10, function()
            LOCK(dirty_inner, self)
        end)
    end

    local n = select("#", ...)
    for i = 1, n do
        local uuid = select(i, ...)
        get(self, uuid)[nm] = nil
        utable.sub(indirty, uuid)[nm] = true
    end
end

function _M.get(self, uuid)
    local subtab = get(self, uuid)
    local nmtab = indirty[uuid]
    if nmtab then
        indirty[uuid] = nil
        for nm in pairs(nmtab) do subtab[nm] = CALL[nm](self, uuid) end
    end
    local ret = {}
    for _, list in pairs(subtab) do
        for _, effect in ipairs(list) do insert(ret, effect) end
    end
    return ret
end

function _M.del(_, uuid)
    CACHE[uuid] = nil
    indirty[uuid] = nil
end

return _M
