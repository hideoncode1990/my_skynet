local ustring = require "util.string"

local thesp<const> = string.byte(":")
local thespkey<const> = "__#@params@#__"

local function split(s)
    if s == "/" then return "__base" end
    return ustring.splitrow(s:sub(2), "/")
end

local database = {}

local function query(db, key, ...)
    if key == nil then
        return db
    else
        if db then
            local dbn = db[key]
            if dbn then
                return query(dbn, ...)
            else
                local spt = db[thespkey]
                if spt then
                    for k, sdb in pairs(spt) do
                        local r, params = query(sdb, ...)
                        if r then
                            if not params then
                                params = {}
                            end
                            params[k] = key
                            return r, params
                        end
                    end
                end
            end
        end
    end
end

local function nextroute(db, key)
    local ret
    if string.byte(key, 1) == thesp then
        local spt = db[thespkey]
        if not spt then
            spt = {}
            db[thespkey] = spt
        end
        key = string.sub(key, 2)
        ret = spt[key]
        if not ret then
            ret = {}
            spt[key] = ret
        end
    else
        ret = db[key]
        if not ret then
            ret = {}
            db[key] = ret
        end
    end
    return ret
end

local select = select
local function update(db, val, method, key, ...)
    if select("#", ...) == 0 then
        assert(type(val) == 'function' or type(val) == 'table')

        local rt = nextroute(db, key)
        if type(method) == 'table' then
            assert(#method > 0, 'empty method')
            for _, m in ipairs(method) do rt[string.upper(m)] = val end
        else
            rt[string.upper(method)] = val
        end
        return rt
    else
        local rt = nextroute(db, key)
        return update(rt, val, method, ...)
    end
end

local function index(k, ...)
    return query(database, k, ...)
end

local cache = setmetatable({}, {__mode = 'v'})
local _M = {}

--- @param path string
--- @return table
--- @return table
function _M.route(path)
    local route = cache[path]
    if route then return route end

    local params
    route, params = index(split(path))
    if route then
        if not params then cache[path] = route end
        return route, params
    end
end

function _M.__call(_, path, method, func)
    return _M.reg(path, method, func)
end

function _M.__pairs()
    return pairs(database)
end

function _M.__newindex()
    assert(false)
end

function _M.reg(path, method, func)
    print(path, method, func)
    return update(database, func, method, split(path))
end

return setmetatable(_M, _M)
