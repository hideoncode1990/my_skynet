local skynet = require "skynet"
local ceilmap = require "ceilmap.c"
local client = require "client"
local move_hex = require "battle.move_hex"
local cfgdata = require "cfg.data"
local log = require "log"
local assert = assert
local STOPCFG

local tremove = table.remove
local tinsert = table.insert
local pushobjs = client.pushobjs
local floor = math.floor
local sqrt = math.sqrt

skynet.init(function()
    STOPCFG = cfgdata.stopinfo
end)
return function(width, height, stop)
    local plys = {}
    local OBJS = {}
    local OBJ_MAP = {}
    local ceils, neibos = {}, {}
    local skip

    assert(stop)
    local CM, size = ceilmap.new(width, height)
    local content = STOPCFG[stop .. ".stop"]
    local j = string.find(content, "@")
    if j then content = string.sub(content, 1, j - 1) end
    CM:stop_init(content)
    local _M = {size = size, ceils = ceils, neibos = neibos}

    local function get(id)
        -- for _, o in ipairs(OBJS) do if id == o.id then return o end end
        return OBJ_MAP[id]
    end

    local function add(obj)
        tinsert(OBJS, obj)
        OBJ_MAP[obj.id] = obj
    end

    local function del(id)
        for i, o in ipairs(OBJS) do
            if id == o.id then
                OBJ_MAP[id] = nil
                return tremove(OBJS, i)
            end
        end
    end

    function _M.sendall(name, msg, force)
        if skip and not force then return 0, 0 end
        return pushobjs(plys, name, msg)
    end

    function _M.add_ply(ply)
        plys[ply.rid] = ply
    end

    _M.get = get

    function _M.get_all()
        return OBJS
    end

    local function stop_get(hx, hy)
        return CM:stop_get(hx, hy)
    end

    local function check_hex(hx, hy)
        local maxx, maxy = size.hx, size.hy
        if hx < 0 or hx >= maxx then return false end
        local dy = floor(hx / 2)
        if hy < (0 - dy) or hy > (maxy - 1 - dy) then return false end
        return true
    end

    function _M.check_stop(hx, hy)
        if check_hex(hx, hy) then return stop_get(hx, hy) end
        return true
    end

    local function check_border(x, y)
        if not x then return true end
        local sx = size.x + 0.1
        local sy = size.y + sqrt(3) / 2 + 0.1
        if x < 0 or x > sx then return false end
        if y < 0 or y > sy then return false end
        return true
    end

    local function check_valid(hex, why, info)
        if not check_border(hex.x, hex.y) or not check_hex(hex.hx, hex.hy) then
            ldump({hex = hex, info = info, size = size},
                why or "objmgr check_hex")
            assert(false, "objmgr check_valid")
        end
    end

    local function to_idx(hx, hy)
        return hx * size.hy + hy
    end
    _M.to_idx = to_idx

    function _M.to_hex(pos)
        local hex = CM:pos_to_hex(pos.x, pos.y)
        check_valid(hex)
        hex.idx = to_idx(hex.hx, hex.hy)
        return hex
    end

    function _M.to_pos(hex)
        local nhex = CM:loc_to_pos(hex.hx, hex.hy)
        check_valid(nhex)
        nhex.idx = to_idx(nhex.hx, nhex.hy)
        return nhex
    end

    function _M.index_to_xy(index)
        return CM:index_to_xy(index)
    end

    local function add_to_map(obj)
        local x, y, body = obj.x, obj.y, obj.body
        if obj.pos_idx then
            x, y = _M.index_to_xy(obj.pos_idx)
            obj.x, obj.y = x, y
        end
        assert(x)
        local hex = CM:add(obj.id, x, y, body)
        check_valid(hex)
        hex.idx = to_idx(hex.hx, hex.hy)
        obj.hex = hex
    end

    function _M.add(bctx, obj)
        local id = obj.id
        assert(not get(id))
        add_to_map(obj)
        add(obj)
        move_hex.add(bctx, obj.hex, obj)
        --[[
        log("add obj %s(%f,%f)(%d,%d) masterid:%s", id, obj.x, obj.y,
            obj.hex.hx, obj.hex.hy, obj.masterid or 0)
        -- ]]
        return obj
    end

    function _M.remove(bctx, id)
        local obj = assert(get(id))
        CM:del(id)
        del(id)
        move_hex.del(bctx, obj.hex, obj)
        return obj
    end

    function _M.update(bctx, obj, x, y)
        obj.x, obj.y = x, y
        local hex = CM:move(obj.id, x, y)
        check_valid(hex)
        hex.idx = to_idx(hex.hx, hex.hy)
        move_hex.move(bctx, obj, obj.hex, hex)
        obj.hex = hex
    end

    function _M.find_objects(type, points)
        return CM:calc(type, points)
    end

    function _M.findpath(start, to)
        local ok, list = CM:findpath(start.x, start.y, to.x, to.y, to.body)
        -- if ok then return list end
        for _, hex in pairs(list) do hex.idx = to_idx(hex.hx, hex.hy) end
        return list, ok
    end

    function _M.find_usable_hex(hex)
        local hx, hy = hex.hx, hex.hy
        local _hex = CM:find_usable(hx, hy)
        check_valid(_hex)
        _hex.idx = to_idx(_hex.hx, _hex.hy)
        return _hex
    end

    function _M.exist_hero(hex)
        local cnt = _M.get_obj_cnt(hex)
        return cnt > 0
    end

    function _M.get_obj_cnt(hex)
        local hx, hy = hex.hx, hex.hy
        local cnt = CM:get_obj_cnt(hx, hy)
        return cnt
    end

    function _M.check_line(from, to)
        -- 如果没有遇到阻挡，也会将越界的目标点校正
        local stop_pos, ok = CM:check_line(from.x, from.y, to.x, to.y)
        check_valid(stop_pos)
        stop_pos.idx = to_idx(stop_pos.hx, stop_pos.hy)
        return ok and stop_pos, stop_pos
    end

    function _M.find_dest_line(from, to, dist)
        local dest = CM:find_dest_line(from.x, from.y, to.x, to.y, dist)
        --[[
        ldump({ok, dest}, string.format(" find_dest_line (%f,%f) -> (%f,%f)",
                                        from.x, from.y, to.x, to.y))
        -- ]]
        check_valid(dest)
        dest.idx = to_idx(dest.hx, dest.hy)
        return dest
    end

    function _M.set_skip()
        skip = true
    end

    function _M.setpos(bctx, self, pos)
        local x, y = pos.x, pos.y
        _M.update(bctx, self, x, y)
    end

    return _M
end
