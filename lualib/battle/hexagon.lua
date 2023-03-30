local vector2_distance = require"battle.vector2".distance
local abs = math.abs
local insert = table.insert

local _M = {}

local neibo_dir = {{1, 0}, {1, -1}, {0, -1}, {-1, 0}, {-1, 1}, {0, 1}};
local NEIBO_CNT<const> = #neibo_dir
local function get_neibo(dir, hex)
    local dhex = neibo_dir[dir]
    local hx = hex.hx + dhex[1]
    local hy = hex.hy + dhex[2]
    return hx, hy
end

local function check_neibo(l_hex, r_hex)
    return abs(l_hex.hx - r_hex.hx) <= 1 and abs(l_hex.hy - r_hex.hy) <= 1 and
               not (l_hex.hx == r_hex.hx and l_hex.hy == r_hex.hy)
end

function _M.check_neibo(hex, ...)
    local neibos = {...}
    for _, neibo in ipairs(neibos) do
        if not check_neibo(hex, neibo) then return false end
    end
    return true
end

function _M.get_neibos(bctx, hex)
    local r = {}
    local objmgr = bctx.objmgr
    local check_stop = objmgr.check_stop
    local to_idx = objmgr.to_idx
    for i = 1, NEIBO_CNT do
        local hx, hy = get_neibo(i, hex)
        if not check_stop(hx, hy) then insert(r, to_idx(hx, hy)) end
    end
    return r
end

function _M.near_center(self)
    if vector2_distance(self, self.hex) <= 0.1 then return true end
    return false
end

function _M.same_location(hex1, hex2)
    if not hex1 or not hex2 then return false end
    return hex1.hx == hex2.hx and hex1.hy == hex2.hy
end

function _M.find_back(bctx, self, target)
    local hx, hy
    local s_hex = self.hex
    local t_hex = target.hex
    if t_hex.hx > s_hex.hx then
        hx = t_hex.hx + 1
    elseif t_hex.hx == s_hex.hx then
        hx = t_hex.hx
    else
        hx = t_hex.hx - 1
    end
    if t_hex.hy > s_hex.hy then
        hy = t_hex.hy + 1
    elseif t_hex.hy == s_hex.hy then
        hy = t_hex.hy
    else
        hy = t_hex.hy - 1
    end

    if (hx ~= s_hex.hx and hy ~= s_hex.hy) or
        (hx ~= t_hex.hx and hy ~= t_hex.hy) then
        if not bctx.objmgr.check_stop(hx, hy) then
            local to_idx = bctx.objmgr.to_idx
            return {hx = hx, hy = hy, idx = to_idx(hx, hy)}
        end
    end
end

function _M.find_front(bctx, self, target)
    local hx, hy
    local s_hex = self.hex
    local t_hex = target.hex
    if t_hex.hx > s_hex.hx then
        hx = s_hex.hx + 1
    elseif t_hex.hx == s_hex.hx then
        hx = s_hex.hx
    else
        hx = s_hex.hx - 1
    end
    if t_hex.hy > s_hex.hy then
        hy = s_hex.hy + 1
    elseif t_hex.hy == s_hex.hy then
        hy = s_hex.hy
    else
        hy = s_hex.hy - 1
    end

    if (hx ~= s_hex.hx and hy ~= s_hex.hy) or
        (hx ~= t_hex.hx and hy ~= t_hex.hy) then
        if not bctx.objmgr.check_stop(hx, hy) then
            local to_idx = bctx.objmgr.to_idx
            return {hx = hx, hy = hy, idx = to_idx(hx, hy)}
        end
    end
end

function _M.rand_near(bctx, hex, r)
    local check_stop = bctx.objmgr.check_stop
    for i = 1, NEIBO_CNT do
        local dir = (r + i) % NEIBO_CNT + 1
        local hx, hy = get_neibo(dir, hex)
        if not check_stop(hx, hy) then
            local to_idx = bctx.objmgr.to_idx
            return {hx = hx, hy = hy, idx = to_idx(hx, hy)}
        end
    end
end

return _M
