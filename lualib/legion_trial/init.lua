local skynet = require "skynet"
local cfgdata = require "cfg.data"
local cache = require "legion_trial.cache"("scene")
local client = require "client"
local battle_hero = require "legion_trial.battle_hero"
local monster = require "legion_trial.object.monster"
local objtype = require "legion_trial.objtype"
local battle = require "battle"
local wintype = require "battle.win_type"
local card = require "legion_trial.card"
local legion_obj = require "legion_trial.object"
local NM<const> = "legion_trial"

local _M = {}
local schema = require "mongo.schema"
cache.schema(schema.OBJ {
    current = schema.ORI,
    choosed = schema.ORI,
    sceneid = schema.ORI,
    endti = schema.ORI,
    path = schema.ORI,
    ver = schema.ORI
})

local BASIC, SCENE_CFG
skynet.init(function()
    BASIC = cfgdata.basic
    SCENE_CFG = cfgdata.legion_trial_scene
end)

local function init_scene(self, C, sceneid)
    local scene_cfg = SCENE_CFG[sceneid]
    local born = scene_cfg.born
    -- C.ver = BASIC.legion_ver
    C.current = born
    C.sceneid = sceneid
    C.choosed = nil
    C.path = nil
    -- if restart then C.endti = calc_time(self) end
    legion_obj.init_objs(self, sceneid, born)
    card.trigger("mapid", sceneid, self)
    cache.dirty(self)
end

local function enter_scene(self, C)
    client.push(self, "legion_trial_scene", C)
    C.objs = legion_obj.enter(self)
    battle_hero.enter(self)
    card.enter(self)
end

function _M.start(self, reset)
    if reset then _M.reset(self) end
    local new, ver
    local C = cache.get(self)
    if not C.current then
        init_scene(self, C, BASIC.legion_trial_scene)
        new = true
        ver = BASIC.legion_ver
        card.trigger("mapid", C.sceneid, self)
    end
    enter_scene(self, C)
    return {new = new, ver = ver, sceneid = C.sceneid, current = C.current}
end

local function unlink(self, sceneid, objs, nextpos, dels)
    for _, p in ipairs(nextpos) do
        local obj = objs[p]
        if obj then
            obj.link = obj.link - 1
            legion_obj.dirty(self, obj)
            if obj.link <= 0 then
                objs[p] = nil
                local _nextpos = legion_obj.del(self, obj, sceneid, p)
                table.insert(dels, p)
                unlink(self, sceneid, objs, _nextpos, dels)
            end
        end
    end
end

local function del(self, del_link, C, ...)
    local objs = C.objs
    local list = {...}
    local dels = {}
    local sceneid = C.sceneid
    for _, pos in pairs(list) do
        local obj = objs[pos]
        if obj then
            objs[pos] = nil
            local nextpos = legion_obj.del(self, obj, sceneid, pos)
            table.insert(dels, pos)
            if del_link then
                unlink(self, sceneid, objs, nextpos, dels)
            end
        end
    end
    client.push(self, "legion_trial_del", {objs = dels})
end

local function move(self, pos)
    local C = cache.get(self)
    local current
    current, C.choosed = C.current, nil
    if current == pos then return end
    C.current = pos
    local path = cache.getsub(self, "path")
    table.insert(path, current)
    client.push(self, "legion_trial_move", {current = pos})
end

local function finish(self, C, pos)
    del(self, false, C, pos)
    local current = C.current
    move(self, pos)
    if current ~= pos then
        legion_obj.trigger_new(self, C.objs, C.sceneid, pos)
    end
    cache.dirty(self)
end

local function select(self, C, index)
    local pos = C.choosed
    local objs = C.objs
    local obj = objs[pos]
    local ok, e = legion_obj.select(self, obj, index)
    if not ok then return false, e end
    finish(self, C, pos)
    return true, 0, {sceneid = C.sceneid, current = C.current}
end

local function choose(self, C, pos)
    if C.choosed then return true end
    local ok, dels = legion_obj.check_move(C.sceneid, C.current, pos, C.objs)
    if not ok then return false end
    if next(dels) then del(self, true, C, table.unpack(dels)) end
    C.choosed = pos
    cache.dirty(self)
    return true
end

function _M.select(self, pos, index)
    local C = cache.get(self)
    if not C.choosed then
        local ok = choose(self, C, pos)
        if not ok then return 3 end
    end
    if pos ~= C.choosed then return 4 end
    local _, e, ret = select(self, C, index)
    return e, ret
end

function _M.choose(self, pos)
    local C = cache.get(self)
    if C.choosed then return 3 end
    if not choose(self, C, pos) then return 4 end
    return 0, {sceneid = C.sceneid, current = C.current}
end

function _M.close(self, pos)
    local C = cache.get(self)
    if not C.choosed then return 3 end
    if pos ~= C.choosed then return 4 end
    finish(self, C, pos)
    return 0, {sceneid = C.sceneid, current = C.current}
end

function _M.buy(self, pos, index)
    local C = cache.get(self)
    local choosed = C.choosed
    if not choosed then return 3 end
    if pos ~= choosed then return 4 end
    local obj = C.objs[choosed]
    local ok, e = legion_obj.buy(self, obj, index)
    if not ok then return e + 4 end
    return 0, {sceneid = C.sceneid, current = C.current}
end

local function enter_nextfloor(self, sceneid)
    local C = cache.get(self)
    legion_obj.clean(self)
    init_scene(self, C, sceneid)
    enter_scene(self, C)
end

function _M.transport(self, pos)
    local C = cache.get(self)
    if not C.choosed then
        local ok = choose(self, C, pos)
        if not ok then return 3 end
    end
    if pos ~= C.choosed then return 4 end
    local obj = C.objs[pos]
    local sceneid = legion_obj.transport(self, obj)
    enter_nextfloor(self, sceneid)
    card.trigger("mapid", sceneid, self)
    return 0, {sceneid = C.sceneid, current = C.current}
end

function _M.fight(self, pos, bi, herolist)
    local C = cache.get(self)
    local choosed = C.choosed
    if not choosed then return 3 end
    if pos ~= choosed then return 4 end
    local obj = C.objs[pos]
    if obj.type ~= objtype.monster then return 5 end

    local left, e = battle_hero.create_heroes(self, herolist)
    if not left then return e + 5 end
    local right = monster.create_monsters(self, obj.uuid)

    local sceneid = C.sceneid
    local scene_cfg = SCENE_CFG[sceneid]
    local ctx<close> = battle.create(NM, scene_cfg.battle, {
        auto = bi.auto,
        multi_speed = bi.multi_speed,
        no_play = bi.no_play
    })
    if not battle.join(ctx, self) then return 9 end

    battle.start(ctx, left, right, function(_ok, ret)
        if not _ok then return battle.abnormal_push(self) end
        if ret.restart or ret.terminate then
            return battle.push(self, ret)
        end
        local over_ret = {
            pos = pos,
            win = ret.win,
            reward = obj.reward,
            pass = obj.pass,
            floor = scene_cfg.floor,
            objid = obj.objid,
            ret = ret,
            sceneid = sceneid,
            current = C.current
        }
        if ret.win == wintype.win then
            finish(self, C, pos)
            if C.objs[C.current] then C.choosed = C.current end
            cache.dirty(self)
            card.trigger("victory", 1, self)
        else
            local last_attrs = {}
            local r_ret = ret.right
            for _, o in ipairs(right.heroes) do
                local r = r_ret[o.id]
                r.hpmax = o.baseattrs.hpmax
                r.tpvmax = o.baseattrs.tpvmax
                last_attrs[o.pos] = r
            end
            monster.attr_change(self, obj.uuid, last_attrs)
        end
        local l_ret = ret.left
        local last_attrs = {}
        for _, o in ipairs(left.heroes) do
            local r = l_ret[o.id]
            r.hpmax = o.baseattrs.hpmax
            r.tpvmax = o.baseattrs.tpvmax
            r.cfgid = o.cfgid
            r.level = o.level
            last_attrs[o.id] = r
        end
        battle_hero.attr_changes(self, last_attrs)
        skynet.send(self.addr, "lua", "legion_trial_battleover", over_ret)
    end)
    return 0, {sceneid = sceneid, current = C.current}
end

function _M.revive(self)
    battle_hero.all_hptpv_full(self)
    card.trigger("revival", 1, self)
    local C = cache.get(self)
    return 0, {sceneid = C.sceneid, current = C.current}
end

function _M.add_card(self, id, cnt)
    for _ = 1, cnt do card.addbag(self, id) end
end

function _M.reset(self)
    cache.clean(self)
    legion_obj.clean(self)
    battle_hero.clean(self)
    card.clean(self)
end

return _M
