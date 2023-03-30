local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local utable = require "util.table"
local net = require "robot.net"
local timer = require "timer"
local event = require "robot.event"
local herobag = require "robot.herobag"
local _H = require "handler.client"

local insert = table.insert
local remove = table.remove
local sort = table.sort
local sub = utable.sub
local getsub = utable.getsub

local POS = {1, 2, 3, 4}

local EQINFO, EQBODY, EQBAG, EQJOB, BAGCNT = {}, {}, {}, {}, 0
local CFG, CFG_REFINE, CFG_EXP
skynet.init(function()
    CFG, CFG_REFINE, CFG_EXP = cfgproxy("equip", "equip_refine", "equip_exp")
end)

-- .equip_info {
--     uuid 0:integer
--     id 1:integer
--     level 2:integer
--     exp 3:integer
--     feature 4:integer
--     owner 5:integer
--     pos 6:integer
--     new_feature 7:integer
--     job
--     cfgpos
--     mark
-- }

require "util"
local LOGTAB = {}
local function addlog(uuid, str)
    local tab = sub(LOGTAB, uuid)
    insert(tab, str)
end

local function sort_func(a, b)
    return EQINFO[a].mark > EQINFO[b].mark
end

local function add_in_EQJOB(_, uuid, job, pos)
    local tab = getsub(EQJOB, job, pos)
    insert(tab, uuid)
    sort(tab, sort_func)
    BAGCNT = BAGCNT + 1
    EQBAG[uuid] = true
end

local function remove_from_EQJOB(_, uuid, job, pos)
    local tab = EQJOB[job][pos]
    for k, _uuid in ipairs(tab) do
        if _uuid == uuid then
            table.remove(tab, k)
            BAGCNT = BAGCNT - 1
            EQBAG[uuid] = nil
            return
        end
    end
    assert(false)
end

local function find_equip(_, hero, putontab, putondirty, bagcnt)
    local hero_uuid = hero.uuid
    local eqbody = EQBODY[hero_uuid]

    for _, pos in ipairs(POS) do
        local eqjob = getsub(EQJOB, hero.cfg.job, pos)
        local equip
        if eqbody then equip = EQINFO[eqbody[pos]] end

        local mark = -1
        if equip then mark = equip.mark end
        for i = 1, #eqjob do
            local uuid = eqjob[i]
            if not putondirty[uuid] then
                local eqdata = EQINFO[uuid]
                assert(not eqdata.owner)
                if eqdata.mark > mark then
                    local eqtab = sub(putontab, hero_uuid)
                    insert(eqtab, uuid)
                    putondirty[uuid] = true
                    bagcnt = bagcnt - 1
                    if bagcnt <= 0 then return end
                    break
                end
            end
        end
    end
    return true
end

local function puton_onekey(self, putontab)
    local result = true
    if not next(putontab) then return result end

    for hero_uuid, uuids in pairs(putontab) do
        local ret = net.request(self, 300, "equip_puton_onekey",
            {hero_uuid = hero_uuid, uuids = uuids})
        local e = ret.e
        if e ~= 0 then
            result = false

            pdump({hero_uuid = hero_uuid, uuids = uuids},
                "equip_puton_onekey error_" .. e .. "_" .. self.rname)
        else
            -- pdump({hero_uuid = hero_uuid, uuids = uuids},
            --     "equip_puton_onekey successfully")
        end
    end
    return result
end

local function try_puton_onekey(self, heroes)
    if BAGCNT <= 0 then return end
    local putontab, putondirty, bagcnt = {}, {}, BAGCNT
    heroes = heroes or herobag.query_all()
    for _, hero in pairs(heroes) do
        if not find_equip(self, hero, putontab, putondirty, bagcnt) then
            break
        end
    end
    if not puton_onekey(self, putontab) or bagcnt <= 0 then return end
    return bagcnt
end

-- 只用装备去refine  不涉及用材料去refine

local function makelist(dict)
    local ret = {}
    for uuid in pairs(dict) do insert(ret, uuid) end
    return ret
end

local function calc_refine(self)
    local ret, over = {}, nil
    local EQLIST = makelist(EQBAG)
    for _, hero in pairs(herobag.query_all()) do
        local hero_uuid = hero.uuid
        local body = EQBODY[hero_uuid]
        for _, _uuid in pairs(body or {}) do
            local eqdata = EQINFO[_uuid]
            local equip_cost = {}
            local need_info = {
                uuid = _uuid,
                equip_cost = equip_cost,
                item_cost = {}
            }
            local level, exp = eqdata.level, eqdata.exp
            local cfg = CFG[eqdata.id]
            local cfg_refine = CFG_REFINE[eqdata.mark]
            while true do
                if not cfg_refine[level] or level >= cfg.level_max then
                    break
                end
                local uuid = remove(EQLIST)
                if uuid then
                    local one = EQINFO[uuid]
                    insert(equip_cost, uuid)

                    local add_exp = CFG_EXP[one.mark][one.level] +
                                        CFG[one.id].exp

                    while true do
                        local need_exp = cfg_refine[level].need_exp
                        local overflow = add_exp + exp - need_exp
                        if overflow >= 0 then
                            level, exp = level + 1, 0
                            add_exp = overflow
                            if not cfg_refine[level + 1] or level >=
                                cfg.level_max then
                                break
                            end
                        else
                            exp = exp + add_exp
                            add_exp = 0
                            break
                        end
                    end
                else
                    over = true
                    break
                end
            end
            if next(equip_cost) then insert(ret, need_info) end
            if over then return ret end
        end
    end
    return ret
end

local function refine(self, info)
    if next(info) then
        for _, msg in ipairs(info) do
            local ret = net.request(self, 300, "equip_refine", msg)
            local e = ret.e
            if e ~= 0 then
                pdump(msg, "equip_refine error_" .. e)
                return
            else
                -- pdump(msg, "equip_refine successfully")
            end
        end
    end
end

local function try_refine(self)
    refine(self, calc_refine(self))
end

local incalc
local function try_puton_and_refine(self)
    if not incalc then
        incalc = true
        timer.add(300, function()
            incalc = nil
            if not try_puton_onekey(self) then return end
            skynet.sleep(100)
            try_refine(self) -- 不升级就屏蔽
        end)
    end
end

require "util"
function _H.equip_list(self, msg)
    for _, eqdata in ipairs(msg.list) do
        local uuid, owner, pos = eqdata.uuid, eqdata.owner, eqdata.pos
        EQINFO[uuid] = eqdata

        local cfg = CFG[eqdata.id]
        local job, cfgpos, mark = cfg.job, cfg.pos, cfg.mark

        eqdata.job = job
        eqdata.cfgpos = cfgpos
        eqdata.mark = mark
        eqdata.level = eqdata.level or 0
        eqdata.exp = eqdata.exp or 0

        if owner then
            local body = sub(EQBODY, owner)
            assert(not body[pos])
            body[pos] = uuid
            -- addlog(uuid, "init_in_body_" .. owner)
        else
            local eqjob = getsub(EQJOB, job, cfgpos)
            insert(eqjob, uuid)
            BAGCNT = BAGCNT + 1
            EQBAG[uuid] = true
            -- addlog(uuid, "init_in_bag")
        end
    end

    for _, v in pairs(EQJOB) do
        for _, m in pairs(v) do sort(m, sort_func) end
    end
    try_puton_and_refine(self)
end

local function takeoff_inner(eqdata)
    local uuid = eqdata.uuid
    local pos, owner = assert(eqdata.pos), assert(eqdata.owner)
    eqdata.owner = nil
    eqdata.pos = nil

    local body = sub(EQBODY, owner)
    local uuid_old = assert(body[pos])
    if uuid_old == uuid then
        body[pos] = nil
        if not next(body) then EQBODY[owner] = nil end
    end
end

-- 获得一件新装备一定是会先添加到装备背包里面
-- 换下来的装备不算是新添加装备
function _H.equip_bagadd(self, msg)
    for _, eqdata in ipairs(msg.list) do
        local uuid = eqdata.uuid
        assert(not EQINFO[uuid] and not eqdata.onwer and not eqdata.pos)

        local cfg = CFG[eqdata.id]
        local job, cfgpos, mark = cfg.job, cfg.pos, cfg.mark
        eqdata.job = job
        eqdata.cfgpos = cfgpos
        eqdata.mark = mark

        EQINFO[uuid] = eqdata
        add_in_EQJOB(self, uuid, job, cfgpos)
        -- addlog(uuid, "add_in_bag")
    end
    try_puton_and_refine(self)
end

-- 删除装备 只会是装备背包里面的装备被吃掉的情况
-- 所以一定是背包删除装备 此装备 删除时，一定没有pos 和owner字段
function _H.equip_bagdel(self, msg)
    for _, uuid in ipairs(msg.list) do
        local eqdata = EQINFO[uuid]
        assert(not eqdata.pos and not eqdata.owner)

        EQINFO[uuid] = nil
        remove_from_EQJOB(self, uuid, eqdata.job, eqdata.cfgpos)
        -- addlog(uuid, "del_in_bag")
    end
end

-- 被穿上的装备  可能是在背包上 也可能在另外一个英雄身上
function _H.equip_puton(self, msg)
    for _, v in ipairs(msg.list) do
        local uuid, owner, pos = v.uuid, v.owner, v.pos
        assert(uuid and owner and pos)
        assert(herobag.query(self, owner))

        local eqdata = EQINFO[uuid]

        -- 如果这个装备本来就在另外一个英雄身上，就先脱下
        if eqdata.owner then
            takeoff_inner(eqdata)
            -- addlog(uuid,
            -- "puton_oldowner_" .. eqdata.owner .. "newwener_" .. owner)
        else
            remove_from_EQJOB(self, uuid, eqdata.job, eqdata.cfgpos)
            -- addlog(uuid, "puton_no_oldowner_before" .. owner)
        end

        eqdata.pos = pos
        eqdata.owner = owner
        local body = sub(EQBODY, owner)
        body[pos] = eqdata.uuid
    end
end

function _H.equip_takeoff(self, msg)
    for _, uuid in ipairs(msg.list) do
        local eqdata = EQINFO[uuid]
        -- local oldowner = eqdata.owner
        takeoff_inner(eqdata)
        add_in_EQJOB(self, uuid, eqdata.job, eqdata.cfgpos)
        -- addlog(uuid, "takeoff_" .. oldowner)
    end
    try_puton_and_refine(self)
end

-- stageup的装备一定在身上
function _H.equip_stageup(self, msg)
    local uuid = msg.uuid
    local id = msg.id
    local eqdata = EQINFO[uuid]
    eqdata.id = id -- 换id
end

-- 每次获得新英雄，就试图给该英雄穿上当时背包里最好的装备
event.reg("hero_add", try_puton_and_refine)
