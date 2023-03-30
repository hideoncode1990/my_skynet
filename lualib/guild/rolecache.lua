local skynet = require "skynet"
local collection, delay = "guildrole", 300
local mongo = require("mongo.help.one")("DB_FUNC", collection)
local mem_schema = require"guild.schema".mem_schema

local _M = {}

local DIRTY
local dirty_cache = {}

local MEMBERS = {}

local function saveone(rid, query, data, ...)
    dirty_cache[rid] = nil
    return mongo("safe", "update", collection, query, data, ...)
end

local function save()
    DIRTY = nil
    if next(dirty_cache) then
        local ds
        ds, dirty_cache = dirty_cache, {}
        for rid in pairs(ds) do
            local role = MEMBERS[rid]
            if role then
                saveone(rid, {rid = rid}, mem_schema.encode(role))
            end
        end
    end
end

function _M.load(gid)
    local d = mongo("findall", collection, {gid = gid}, {_id = 0})
    for _, role in pairs(d) do
        mem_schema.decode(role)
        MEMBERS[role.rid] = role
    end
    return MEMBERS
end

function _M.loadone(rid, filter)
    local d = mongo("findone", collection, {rid = rid}, filter)
    if d then d = mem_schema.decode(d) end
    return d
end

function _M.dirty(...)
    for _, rid in pairs({...}) do dirty_cache[rid] = true end
    if not DIRTY then
        DIRTY = true
        skynet.timeout(delay, function()
            if DIRTY then save() end
        end)
    end
end

function _M.save(role, query, data, ...)
    local rid = role.rid
    query = query or {rid = rid}
    data = data or mem_schema.encode(role)
    return saveone(rid, query, data, ...)
end

_M.unload = function()
    while DIRTY do save() end
end

return _M
