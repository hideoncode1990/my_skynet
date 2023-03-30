local vector2_distance = require"battle.vector2".distance
local insert = table.insert
local object = require "battle.object"
local _M = {}

local STRATEGY_TYPE_BIT<const> = 32 -- 0 enemy; 1 friend
local STRATEGY_TYPE_MASK<const> = STRATEGY_TYPE_BIT - 1
local st_self<const> = 1 -- 自身
local st_nearest_distance<const> = 2 -- 优先距离最近的敌人
local st_furthest_distance<const> = 3 -- 优先距离最远的敌人
local st_least_hp<const> = 4 -- 优先血量最少的敌人
local st_undermost_zdl<const> = 5 -- 优先zdl最低的敌人
local st_upmost_zdl<const> = 6 -- 优先zdl最高的敌人
local st_most_hp<const> = 7 -- 优先血量最多的敌人

local b_util_now = require"battle.util".now
local log = require "log"
function _M.find_target_poly(bctx, self, vertexs, max, check, ...)
    local objmgr = bctx.objmgr
    local t, c = objmgr.find_objects("P", vertexs)
    local r = {}
    local cnt = 0
    local filter = {}
    for _, id in ipairs(t) do
        if not filter[id] then
            filter[id] = true
            local o = objmgr.get(id)
            if check(self, o, ...) then
                insert(r, o)
                cnt = cnt + 1
                if cnt >= max then break end
            end
        end
    end
    return r, c
end

function _M.find_target_circle(bctx, self, center, radius, max, check, ...)
    local objmgr = bctx.objmgr
    local t, c = objmgr.find_objects("C",
        {x = center.x, y = center.y, r = radius})
    local r = {}
    local cnt = 0
    local filter = {}
    for _, id in ipairs(t) do
        if not filter[id] then
            filter[id] = true
            local o = objmgr.get(id)
            if check(self, o, ...) then
                insert(r, o)
                cnt = cnt + 1
                if cnt >= max then break end
            end
        end
    end
    return r, c
end

function _M.find_target_all(bctx, self, check, ...)
    local objmgr = bctx.objmgr
    local objs = objmgr.get_all()
    local r = {}
    for _, o in ipairs(objs) do if check(self, o, ...) then insert(r, o) end end
    return r
end

function _M.checkenemy(src, o, tobj, ecfg)
    if ecfg.findtarget_notarget and tobj.id == o.id then return false end
    if ecfg.findtarget_noself and src.id == o.id then return false end
    if ecfg.findtarget_onlyhero and not object.check_hero(o) then
        return false
    end
    if not object.check_enemy(src, o) or not object.can_attacked(o) then
        return false
    end
    local tag = ecfg.findtarget_tag
    if tag and not object.check_tag(o, tag[1], tag[2]) then return false end
    return true
end

function _M.checkfriend(src, o, tobj, ecfg)
    if ecfg.findtarget_notarget and tobj.id == o.id then return false end
    if ecfg.findtarget_noself and src.id == o.id then return false end
    if ecfg.findtarget_onlyhero and not object.check_hero(o) then
        return false
    end
    if not object.check_friend(src, o) then return false end
    local tag = ecfg.findtarget_tag
    if tag and not object.check_tag(o, tag[1], tag[2]) then return false end
    return true
end

local function strategy_check_enemy(bctx, self, o)
    if object.select_enemy(bctx, self, o) and object.can_attacked(o) then
        return true
    end
    return false
end

local function strategy_check_friend(bctx, self, o)
    if not object.is_dead(o) and object.check_friend(self, o) then
        return true
    end
    return false
end

local function which_check(strategy)
    local _type = strategy & STRATEGY_TYPE_BIT
    local strategy_code = strategy & STRATEGY_TYPE_MASK
    if _type == 0 then
        return strategy_check_enemy, strategy_code
    else
        return strategy_check_friend, strategy_code
    end
end

function _M.find_target_strategy(bctx, self, strategy)
    if strategy == st_self then return true, self end -- 以自身为目标
    local objmgr = bctx.objmgr
    local t = objmgr.get_all()
    local farthest, closest, minhp, maxhp
    local minzdl, maxzdl
    local sobj
    local check, code = which_check(strategy)
    for _, o in ipairs(t) do
        if check(bctx, self, o) then
            if code == st_nearest_distance then -- 优先距离近的
                local distance = vector2_distance(self, o)
                if not closest or distance < closest then
                    closest = distance
                    sobj = o
                end
            elseif code == st_furthest_distance then -- 优先距离最远的
                local distance = vector2_distance(self, o)
                if not farthest or distance > farthest then
                    farthest = distance
                    sobj = o
                end
            elseif code == st_least_hp then -- 优先血量少的
                if not minhp or o.attrs.hp < minhp then
                    minhp = o.attrs.hp
                    sobj = o
                end
            elseif code == st_most_hp then -- 优先血量多的
                if not maxhp or o.attrs.hp > maxhp then
                    maxhp = o.attrs.hp
                    sobj = o
                end
            elseif code == st_undermost_zdl then -- 优先zdl最低
                if not minzdl or o.zdl < minzdl then
                    minzdl = o.zdl
                    sobj = o
                end
            elseif code == st_upmost_zdl then -- 优先zdl最高
                if not maxzdl or o.zdl > maxzdl then
                    maxzdl = o.zdl
                    sobj = o
                end
            end
        end
    end
    if sobj then return true, sobj end
    return false
end

return _M
