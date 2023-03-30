local skynet = require "skynet"
local client = require "client.mods"
local hattrs = require "hero.attrs"
local cfgproxy = require "cfg.proxy"
local award = require "role.award"
local uattrs = require "util.attrs"
local hinit = require "hero"
local heqlib = require "hero.eqlib"
local awardtype = require "role.award.type"
local flowlog = require "flowlog"
local cache = require("mongo.role")("equips")
local schema = require "mongo.schema"

cache.schema(schema.MAPF("uuid", schema.OBJ {
    uuid = schema.ORI,
    id = schema.ORI,
    exp = schema.ORI,
    feature = schema.ORI,
    new_feature = schema.ORI,
    level = schema.ORI,
    owner = schema.ORI,
    pos = schema.ORI
}))

local create_equip = heqlib.create_equip
local load_other = heqlib.load_other
local append = uattrs.append
local insert = table.insert

local NM<const> = "eqbag"

local _M = {}
local EQBODY, EQCNT = {}, 0

local BASIC, CFG
skynet.init(function()
    BASIC, CFG = cfgproxy("basic", "equip")
end)

local function data_init(_, eqdata)
    local owner = eqdata.owner
    local new
    if owner then
        local body = EQBODY[owner]
        if not body then
            body = {}
            EQBODY[owner] = body
            new = true
        end
        body[assert(eqdata.pos)] = eqdata
    else
        EQCNT = EQCNT + 1
    end
    return new and owner
end

local function data_add(self, eqdata)
    local owner = data_init(self, eqdata)
    if owner then hinit.query(self, owner).equips = EQBODY[owner] end
end

local function data_del(self, eqdata)
    local owner = eqdata.owner
    if owner then
        local body = EQBODY[owner]
        body[eqdata.pos] = nil
        if not next(body) then
            EQBODY[owner] = nil
            hinit.query(self, owner).equips = nil
        end
    end
end

local function isfull(_, n)
    return EQCNT + (n or 1) > BASIC.equip_max
end

local function push_on(self, on)
    if next(on) then client.push(self, NM, "equip_puton", {list = on}) end
end

local function push_off(self, off)
    if next(off) then client.push(self, NM, "equip_takeoff", {list = off}) end
end

local function equip_flowlog(self, opt, option, eqdata, owner)
    local info = {
        opt = opt,
        flag = option.flag,
        arg1 = option.arg1,
        arg2 = option.arg2,
        uuid = eqdata.uuid,
        id = eqdata.id,
        eqlevel = eqdata.level,
        exp = eqdata.exp,
        feature = eqdata.feature or 0,
        owner = owner
    }

    local last, action
    if opt == "add" then
        last = 1
        action = 1
    elseif opt == "del" then
        last = 0
        action = -1
    end
    if last then
        flowlog.platlog(self, "equip", info, "item", {
            tp = awardtype.equip,
            change = 1,
            last = last,
            action = action
        })
    else
        flowlog.role(self, "equip", info)
    end
end

local function create(self, id, feature, C, option)
    local eqdata = create_equip(self, id, feature)
    local uuid = eqdata.uuid
    C[uuid] = eqdata
    cache.dirty(self)

    data_add(self, eqdata)
    equip_flowlog(self, "add", option, eqdata)
    return eqdata
end

local function remove(self, uuid, C, option)
    local eqdata = assert(C[uuid])
    C[uuid] = nil
    cache.dirty(self)

    data_del(self, eqdata)
    EQCNT = EQCNT - 1
    equip_flowlog(self, "del", option, eqdata)
    return eqdata
end

local function puton(self, eqdata, owner, pos, option)
    eqdata.pos = pos
    eqdata.owner = owner
    cache.dirty(self)

    data_add(self, eqdata)
    EQCNT = EQCNT - 1
    -- opt 为 “puton”的，将现在的拥有者记录在owner字段上
    equip_flowlog(self, "puton", option, eqdata, owner)
    return eqdata
end

local function takeoff(self, eqdata, hero_uuid, option)
    data_del(self, eqdata)

    eqdata.pos = nil
    eqdata.owner = nil
    cache.dirty(self)

    eqdata.attrs = nil
    eqdata.zdl = nil
    EQCNT = EQCNT + 1
    -- opt 为 “takeoff”的，将原来的拥有者记录在owner字段上
    equip_flowlog(self, "takeoff", option, eqdata, hero_uuid)
    return eqdata
end

local function add_samemark(_, samemark, hero_uuid, eqdata)
    local mark = CFG[eqdata.id].mark
    local eqbody = EQBODY[hero_uuid]
    local ret = {}
    for _, _eqdata in pairs(eqbody or {}) do
        local _mark = math.min(mark, CFG[_eqdata.id].mark)
        for i = 1, _mark do ret[i] = (ret[i] or 0) + 1 end
    end
    insert(samemark, ret)
end

function _M.puton(self, hero_uuid, uuids, postbl, option)
    local C = cache.get(self)
    local on, off, dirty_uuids, temp = {}, {}, {hero_uuid}, {[hero_uuid] = true}
    local samemark = {}
    for i, pos in ipairs(postbl) do
        local uuid = uuids[i]
        local eqdata = C[uuid]
        local owner = eqdata.owner
        if owner then
            takeoff(self, eqdata, owner, option)
            if not temp[owner] then
                insert(dirty_uuids, owner)
                temp[owner] = true
            end
        end

        local old_eqdata = EQBODY[hero_uuid] and EQBODY[hero_uuid][pos]
        if old_eqdata then
            takeoff(self, old_eqdata, hero_uuid, option)
            if owner then
                insert(on, puton(self, old_eqdata, owner, pos, option))
                add_samemark(self, samemark, owner, old_eqdata)
            else
                insert(off, old_eqdata.uuid)
            end
        end
        insert(on, puton(self, eqdata, hero_uuid, pos, option))
        add_samemark(self, samemark, hero_uuid, eqdata)
    end
    push_on(self, on)
    push_off(self, off)
    return dirty_uuids, samemark
end

local function eqbag_takeoff(self, hero_uuid, pos, option)
    local off_uuid = {}
    if pos then
        local eqdata = EQBODY[hero_uuid][pos]
        takeoff(self, eqdata, hero_uuid, option)
        insert(off_uuid, eqdata.uuid)
    else
        for _, eqdata in pairs(EQBODY[hero_uuid] or {}) do
            takeoff(self, eqdata, hero_uuid, option)
            insert(off_uuid, eqdata.uuid)
        end
    end
    push_off(self, off_uuid)
end

_M.takeoff = eqbag_takeoff

function _M.refine(self, uuid, level, exp, option)
    local eqdata = cache.get(self)[uuid]
    eqdata.level = level
    eqdata.exp = exp
    cache.dirty(self)

    equip_flowlog(self, "refine", option, eqdata)
    return true
end

function _M.dels(self, uuids, option)
    local C = cache.get(self)
    for _, uuid in ipairs(uuids) do
        local eqdata = C[uuid]
        local owner = eqdata.owner
        if owner then takeoff(self, eqdata, owner, option) end
        remove(self, uuid, C, option)
    end
    client.push(self, NM, "equip_bagdel", {list = uuids})
    return true
end

function _M.refeature(self, uuid, option)
    local C = cache.get(self)
    local eqdata = C[uuid]
    local new_feature = heqlib.recreate_feature(self, eqdata.id,
        assert(eqdata.feature))
    eqdata.new_feature = new_feature
    cache.dirty(self)

    option.arg2 = new_feature
    equip_flowlog(self, "refeature", option, eqdata)
    return new_feature
end

function _M.feature_sure(self, uuid, sure, option)
    local C = cache.get(self)
    local eqdata = C[uuid]
    local new_feature = assert(eqdata.new_feature)
    if sure then eqdata.feature = new_feature end
    eqdata.new_feature = nil
    cache.dirty(self)

    equip_flowlog(self, "feature_sure", option, eqdata)
    return true
end

function _M.stageup(self, uuid, option)
    local C = cache.get(self)
    local eqdata = C[uuid]
    local cfg = CFG[eqdata.id]
    local new_id = assert(cfg.advanced)
    eqdata.id = new_id
    cache.dirty(self)

    load_other(self, eqdata)
    equip_flowlog(self, "stageup", option, eqdata)
    client.push(self, NM, "equip_stageup", eqdata)
    return new_id
end

function _M.checkdel(self, uuids)
    local C = cache.get(self)
    for _, uuid in ipairs(uuids) do if not C[uuid] then return false end end
    return true
end

function _M.query_eqbag(self, uuid)
    return cache.get(self)[uuid]
end

function _M.query_eqbody(_, hero_uuid)
    return EQBODY[hero_uuid] or {}
end

function _M.query_eqcfg(_, id)
    return CFG[id]
end

_M.isfull = isfull

require("hero.mod").reg {
    name = NM,
    load = function(self)
        for _, eqdata in pairs(cache.get(self)) do
            data_init(self, eqdata)
        end
    end,
    init = function(_, uuid, obj)
        obj.equips = EQBODY[uuid]
    end,
    enter = function(self)
        local push = {}
        for _, eqdata in pairs(cache.get(self)) do insert(push, eqdata) end
        client.enter(self, NM, "equip_list", {list = push})
    end,
    reset = function(self, uuid, _, option)
        eqbag_takeoff(self, uuid, nil, option)
    end,
    remove = function(self, uuid, _, option)
        eqbag_takeoff(self, uuid, nil, option)
    end
}

award.reg {
    type = awardtype.equip,
    add = function(self, nms, pkts, option, items)
        local C = cache.get(self)
        local list = pkts.equip_bagadd
        nms.equip_bagadd = NM

        for _, cfg in ipairs(items) do
            local id, cnt, feature = cfg[2], cfg[3], cfg[4]
            for _ = 1, cnt do
                insert(list, create(self, id, feature, C, option))
            end
        end
        return true
    end,
    checkadd = function(self, items)
        local n = 0
        for _, cfg in ipairs(items) do
            local id, cnt = cfg[2], cfg[3]
            assert(CFG[id] and cnt > 0)
            n = n + cnt
        end
        return not isfull(self, n)
    end,
    del = function()
        error("no support")
    end,
    checkdel = function()
        error("no support")
    end
}

hattrs.reg(NM, function(self, hero_uuid)
    local body = EQBODY[hero_uuid] or {}
    local ret = {}
    for _, eqdata in pairs(body) do
        load_other(self, eqdata)
        append(ret, eqdata.attrs)
    end
    return ret
end)

heqlib.reg("feature", function(self, eqdata)
    local coe = 0
    local hero_uuid = eqdata.owner
    if hero_uuid then
        local cfg_hero = hinit.query_cfg(self, hero_uuid)
        local feature = eqdata.feature
        local cfg_equip = CFG[eqdata.id]
        if feature and feature == cfg_hero.feature then
            coe = cfg_equip.feature_coe[feature]
        end
    end
    return coe
end)

return _M
