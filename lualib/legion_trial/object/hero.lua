local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local utable = require "util.table"
local cache = require("legion_trial.cache")("hero")
local schema = require "mongo.schema"
cache.schema(schema.NOBJ())
local uniq = require "uniq.c"
local battle_hero = require "legion_trial.battle_hero"
local client = require "client"
local objtype = require "legion_trial.objtype"

local CFG_STAGE, CFG_RAND
skynet.init(function()
    CFG_STAGE, CFG_RAND = cfgproxy("herotower_stage", "herotower_random")
end)
local _M = {}

function _M.enter(self)
    local C = cache.get(self)
    client.push(self, "legion_trial_objs", {objs = C})
    return C
end

function _M.new(self, pos, objid, num)
    local stage = self.ave_stage
    local group = CFG_STAGE[stage].group
    local cfg = CFG_RAND[group]
    local list, size = utable.copy(cfg.list), cfg.size
    local heroes = {}
    for _ = 1, num do
        local ran, pro = math.random(1, size), 0
        for k, v in ipairs(list) do
            local heroid, weight = v[1], v[2]
            pro = pro + weight
            if ran <= pro then
                table.remove(list, k)
                size = size - weight
                table.insert(heroes, {heroid = heroid, group = group})
                break
            end
        end
    end
    local C = cache.get(self)
    local uuid = uniq.uuid()
    local obj = {
        type = objtype.hero,
        uuid = uuid,
        pos = pos,
        objid = objid,
        selects = heroes
    }
    C[uuid] = obj
    cache.dirty(self)
    return obj
end

function _M.select(self, uuid, index)
    local C = cache.get(self)
    local obj = C[uuid]
    local hero = obj.selects[index]
    if not hero then return false, 31 end
    battle_hero.add(self, hero)
    return true
end

function _M.del(self, uuid)
    local C = cache.get(self)
    C[uuid] = nil
    cache.dirty(self)
end

function _M.clean(self)
    cache.clean(self)
end

function _M.dirty(self)
    cache.dirty(self)
end
return _M
