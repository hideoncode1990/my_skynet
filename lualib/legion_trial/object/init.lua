local skynet = require "skynet"
local client = require "client"
local objtype = require "legion_trial.objtype"
local cfgproxy = require "cfg.proxy"

local CFG_POS, CFG_OBJ
skynet.init(function()
    CFG_POS, CFG_OBJ = cfgproxy("legion_trial", "legion_trial_objs")
end)

local CBS = {}
local _M = {}
skynet.init(function()
    for k, _type in pairs(objtype) do
        CBS[_type] = require("legion_trial.object." .. k)
    end
end)

function _M.enter(self)
    local objs = {}
    for _, m in pairs(CBS) do
        local C = m.enter(self)
        for _, o in pairs(C) do objs[o.pos] = o end
    end
    return objs
end

local function push_obj(self, obj)
    client.push(self, "legion_trial_objs", {objs = {[obj.uuid] = obj}})
end

function _M.push(self, obj)
    push_obj(self, obj)
end

local function newobj(self, pos, objid, push, ...)
    local objcfg = CFG_OBJ[objid]
    local o = CBS[objcfg.type].new(self, pos, objid, table.unpack(objcfg.para),
        objcfg.pass, ...)
    if push then push_obj(self, o) end
    -- return {type = objcfg.type, uuid = o.uuid, objid = objid, link = 1}
    o.link = 1
    return o
end

local function init_objs(self, d, cfgs, nextpos)
    for _, v in ipairs(nextpos or {}) do
        local pos = v[1]
        if not d[pos] then
            local poscfg = cfgs[pos]
            local coe, fixed_award, dropid = poscfg.reward_coe,
                poscfg.mon_fixed_award, poscfg.mon_dropid
            d[pos] = newobj(self, pos, poscfg.objid, false, coe, fixed_award,
                dropid)
            init_objs(self, d, cfgs, poscfg.next)
        else
            local obj = d[pos]
            obj.link = obj.link + 1
        end
    end
end

function _M.init_objs(self, sceneid, born)
    local cfgs = CFG_POS[sceneid]
    init_objs(self, {}, cfgs, cfgs[born].next)
end

local function get_nextpos(sceneid, pos)
    local r = {}
    local poscfg = CFG_POS[sceneid][pos]
    for _, v in ipairs(poscfg.next or {}) do table.insert(r, v[1]) end
    for _, v in ipairs(poscfg.new or {}) do table.insert(r, v[1]) end
    return r
end

function _M.del(self, obj, sceneid, pos)
    CBS[obj.type].del(self, obj.uuid)
    return get_nextpos(sceneid, pos)
end

function _M.trigger_new(self, objs, sceneid, pos)
    local newpos = CFG_POS[sceneid][pos].new
    if not newpos then return end
    local mainline = self.mainline
    for _, v in ipairs(newpos) do
        local _pos, _objid, _mainline = v[1], v[2], v[3] or mainline
        if not objs[_pos] then
            if mainline >= _mainline then
                local poscfg = CFG_POS[sceneid][_pos]
                local coe, fixed_award, dropid = poscfg.reward_coe,
                    poscfg.mon_fixed_award, poscfg.mon_dropid
                objs[_pos] = newobj(self, _pos, _objid, true, coe, fixed_award,
                    dropid)
            end
        end
    end
end

function _M.check_move(sceneid, current, pos, objs)
    local dels = {}
    if objs[current] and pos ~= current then return false, dels end
    local nextpos = get_nextpos(sceneid, current)
    local find
    for _, p in ipairs(nextpos) do
        if objs[p] then
            if p == pos then
                find = true
            else
                table.insert(dels, p)
            end
        end
    end
    return find, dels
end

function _M.select(self, obj, index)
    local type, uuid = obj.type, obj.uuid
    return CBS[type].select(self, uuid, index)
end

function _M.buy(self, obj, index)
    local type, uuid = obj.type, obj.uuid
    return CBS[type].buy(self, uuid, index)
end

function _M.transport(self, obj)
    local type, uuid = obj.type, obj.uuid
    return CBS[type].transport(self, uuid)
end

function _M.clean(self)
    for _, m in pairs(CBS) do m.clean(self) end
end

function _M.dirty(self, obj)
    CBS[obj.type].dirty(self)
end

return _M
