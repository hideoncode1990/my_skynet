local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local objmgr = require "map.objmgr"
local utable = require "util.table"
local objtype = require "map.objtype"
local _LUA = require "handler.lua"
local map_buff = require "map.buff"
local gird = require "map.gird"

local selftype = require("map.objtype").treasure

local _M = objmgr.class(selftype)

local CNT<const> = 3

local CFG, CFG_GROUP
skynet.init(function()
    CFG, CFG_GROUP = cfgproxy("treasure", "treasure_group")
end)

local function exclude(groupid)
    local cfg_g = CFG_GROUP[groupid]
    local cfg_size, cfg_list = cfg_g.size, cfg_g.list

    local list = utable.copy(cfg_list)
    local d = map_buff.get()
    for i = #list, 1, -1 do
        local id = list[i][1]
        local cfg = CFG[id]
        local cnt = d[id]
        if cnt and cfg.exist then
            if cfg.exist <= cnt then
                local data = table.remove(list, i)
                cfg_size = cfg_size - data[2]
            end
        end
    end
    return cfg_size, list
end

local function random_group(groupid)
    local ret = {}
    local size, list = exclude(groupid)
    for _ = 1, CNT do
        if #list > 0 then
            local ran, pro = math.random(1, size), 0
            for k, v in ipairs(list) do
                local id, weight = v[1], v[2]
                pro = pro + weight
                if ran <= pro then
                    table.remove(list, k)
                    size = size - weight
                    table.insert(ret, id)
                    break
                end
            end
        else
            return ret
        end
    end
    return ret
end

function _M.new(uuid, id, pos, groupid)
    return {pos = pos, uuid = uuid, id = id, buffs = random_group(groupid)}
end

function _M.renew(o)
    return o
end

function _M.pack(self)
    return "map_treasure", self
end

function _LUA.map_buff(rid, uuid, index)
    local ply = objmgr.player()
    assert(rid == ply.uuid)
    local o = objmgr.grab(uuid, objtype.treasure)
    if not o then return false, 2 end

    if not gird.isneibo(ply.pos, o.pos) then return false, 5 end
    local buff_id = o.buffs[index]
    if not buff_id then return false, 9 end

    map_buff.add(buff_id)
    objmgr.del(uuid)
    return true
end

function _LUA.map_buff_gm(_, buff_id, cnt)
    if (require "map.env").mod_nm ~= "secret" then return false, 2 end
    if not CFG[buff_id] then return false, 3 end

    for _ = 1, (cnt or 1) do map_buff.add(buff_id) end
end

return _M
