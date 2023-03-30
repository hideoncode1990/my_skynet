local sqrt = math.sqrt
local math_rad = math.rad
local math_cos = math.cos
local math_sin = math.sin
local math_max = math.max
local _M = {}

function _M.add(vt1, vt2)
    local x, y = vt1.x + vt2.x, vt1.y + vt2.y
    return {x = x, y = y}
end

function _M.sub(vt1, vt2)
    local x, y = vt1.x - vt2.x, vt1.y - vt2.y
    return {x = x, y = y}
end

function _M.opposite(vt)
    local x, y = 0 - vt.x, 0 - vt.y
    return {x = x, y = y}
end

function _M.rotate(ot, vt, angle)
    local rad = math_rad(angle)
    local cosa = math_cos(rad)
    local sina = math_sin(rad)
    ot.x, ot.y = vt.x * cosa + vt.y * sina, vt.y * cosa - vt.x * sina
    return ot
end

function _M.dot(vt1, vt2)
    return vt1.x * vt2.x + vt1.y * vt2.y
end

function _M.normal(ot, vt)
    local t = (vt.x ^ 2 + vt.y ^ 2) ^ (0.5)
    ot.x, ot.y = vt.x / t, vt.y / t
    return ot
end

function _M.scale(ot, vt, sl)
    ot.x, ot.y = vt.x * sl, vt.y * sl
    return ot
end

local function distance(vt1, vt2)
    return sqrt((vt1.x - vt2.x) ^ 2 + (vt1.y - vt2.y) ^ 2)
end
_M.distance = distance

local function move(vt1, vt2, pass, max, offset)
    offset = math_max(0, (offset - 0.1))
    if max <= offset then
        -- print("move1",pass,max,offset,true)
        return {x = vt1.x, y = vt1.y}, true
    end
    local aper = offset / max
    local tx = vt2.x + (vt1.x - vt2.x) * aper
    local ty = vt2.y + (vt1.y - vt2.y) * aper
    local ok = (pass + offset) >= max
    if ok then
        -- print("move2",pass,max,offset,true)
        return {x = tx, y = ty}, true
    else
        -- print("move3",pass,max,offset,false)
        local per = pass / max
        local x = vt1.x + (vt2.x - vt1.x) * per
        local y = vt1.y + (vt2.y - vt1.y) * per
        return {x = x, y = y}, false, {x = tx, y = ty}
    end
end
_M.move = move

function _M.dir_rotate_scale(dir, angle, dist)
    local x, y = dir.x, dir.y
    if angle ~= 0 then
        local rad = math_rad(0 - angle)
        local cosa = math_cos(rad)
        local sina = math_sin(rad)
        x, y = x * cosa + y * sina, y * cosa - x * sina
    end
    local tt = (x ^ 2 + y ^ 2) ^ 0.5
    local s = dist / tt
    return {x = x * s, y = y * s}
end

function _M.movetowards(vt1, vt2, pass, offset)
    local d = distance(vt1, vt2)
    return move(vt1, vt2, pass, d, offset or 0)
end

function _M.eq_zero(vt)
    return vt.x == 0 and vt.y == 0
end

return _M
