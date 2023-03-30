local get_neibos = require"battle.hexagon".get_neibos
local insert = table.insert

local _M = {}

function _M.add(bctx, hex, self)
    local id = self.id
    local ceils = bctx.objmgr.ceils
    local key = assert(hex.idx)
    local ids = ceils[key]
    if not ids then
        ids = {}
        ceils[key] = ids
    end
    ids[id] = true
end

function _M.remove(bctx, hex, self)
    local id = self.id
    local ceils = bctx.objmgr.ceils
    local key = assert(hex.idx)
    local ids = ceils[key]
    if not ids then error("move_hex remove : ceils is nil") end
    ids[id] = nil
    if not next(ids) then ceils[key] = nil end
end

function _M.del(bctx, hex, self)
    local id = self.id
    local ceils = bctx.objmgr.ceils
    local key = assert(hex.idx)
    local ids = ceils[key]
    if ids then
        ids[id] = nil
        if not next(ids) then ceils[key] = nil end
    end
end

function _M.move(bctx, self, from, to)
    local id = self.id
    local ceils = bctx.objmgr.ceils
    local key = assert(from.idx)
    local ids = ceils[key]
    if ids and ids[id] then
        ids[id] = nil
        if not next(ids) then ceils[key] = nil end
        _M.add(bctx, to, self)
    end
end

function _M.cant_arrive(bctx, hex, self)
    local id = self.id
    local ceils = bctx.objmgr.ceils
    local key = assert(hex.idx)
    local ids = ceils[key]
    if ids then
        for _id in pairs(ids) do if _id ~= id then return true end end
    end
    return false
end

function _M.mark_surround(bctx, hex)
    local t_key = assert(hex.idx)
    local neibos = bctx.objmgr.neibos
    local neibo = neibos[t_key]
    if not neibo then
        neibo = {}
        neibos[t_key] = neibo
        local t = get_neibos(bctx, hex)
        for _, key in ipairs(t) do insert(neibo, key) end
    end
    return true
end

function _M.is_surrounded(bctx, hex)
    local objmgr = bctx.objmgr
    local ceils = objmgr.ceils
    local neibos = objmgr.neibos
    local t_key = assert(hex.idx)
    local neibo = neibos[t_key]
    if neibo then
        for _, key in pairs(neibo) do
            local ids = ceils[key]
            if not ids or not next(ids) then
                neibos[t_key] = nil
                return false
            end
        end
        return true
    end
    return false
end

function _M.check_heroin(bctx, hex)
    local ceils = bctx.objmgr.ceils
    local key = assert(hex.idx)
    local ids = ceils[key]
    if ids and next(ids) then return true end
    return false
end

return _M
