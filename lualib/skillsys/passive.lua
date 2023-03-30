local skynet = require "skynet"
local cfgdata = require "cfg.data"
local attrlib = require "util.attrs"
local attr_ids = attrlib.ids
local _BG = require "battle.global"
local skill_sys
local condition = require "skillsys.condition"
local _M = {}

local ipairs = ipairs
local pairs = pairs
local insert = table.insert
local remove = table.remove

local CFG
skynet.init(function()
    skill_sys = require "skillsys.skill_sys"
    CFG = cfgdata.passive_effect
end)

local function trigger_one_passive(bctx, cfg, self, obj, ctx, ...)
    local cond = cfg.condition
    for _, c in ipairs(cond) do
        if not condition(bctx, self, obj, ctx, c, ...) then return false end
    end
    local effectlist = cfg.effects
    if effectlist then
        -- todo
        skill_sys.cast_effectlist(bctx, self, ctx, effectlist, obj,
            obj and obj.x or ctx.x, obj and obj.y or ctx.y, ...)
    end
    return true
end

local function trigger(bctx, passive_ids, self, obj, ctx, ...)
    local times = 0
    for _, id in pairs(passive_ids) do
        local cfg = CFG[id]
        local succ = trigger_one_passive(bctx, cfg, self, obj, ctx, ...)
        if succ then times = times + 1 end
    end
    return times
end

local function passive_trigger(bctx, type, self, obj, ctx, ...)
    local passive_effects = self.passive_effects
    if passive_effects then
        local passive_ids = self.passive_effects[type]
        if passive_ids then
            return trigger(bctx, passive_ids, self, obj, ctx or {}, ...)
        end
    end
    return 0
end

_BG.passive_trigger = passive_trigger

function _BG.passive_trigger_Bi(bctx, type, type_R, self, obj, ctx, ...)
    passive_trigger(bctx, type, self, obj, ctx, ...)
    passive_trigger(bctx, type_R, obj, self, ctx, ...)
end

function _BG.passive_attr(bctx, _type, self, obj, ctx)
    local passive_effects = self.passive_effects
    if passive_effects then
        local passive_ids = passive_effects[_type]
        if passive_ids then
            local ret = {}
            ctx = ctx or {}
            for _, id in pairs(passive_ids) do
                local cfg = CFG[id]
                if trigger_one_passive(bctx, cfg, self, obj, ctx) then
                    local attrs = cfg.attrs
                    for _, attr in ipairs(attrs) do
                        local attr_id, attr_val = attr[1], attr[2]
                        local key = attr_ids[attr_id]
                        ret[key] = (ret[key] or 0) + attr_val
                    end
                end
            end
            return ret
        end
    end
end

local function add(self, id, t_type)
    local passive_effects = self.passive_effects
    local passive_ids = passive_effects[t_type]
    if not passive_ids then
        passive_ids = {}
        passive_effects[t_type] = passive_ids
    end
    insert(passive_ids, id)
end

local function del(self, id, t_type)
    local passive_effects = self.passive_effects
    if passive_effects then
        local passive_ids = passive_effects[t_type]
        if passive_ids then
            for i, _id in ipairs(passive_ids) do
                if _id == id then
                    remove(passive_ids, i)
                    break
                end
            end
        end
    end
end

local function load(bctx, self, ids)
    for _, id in pairs(ids or {}) do
        local cfg = CFG[id]
        local t_type = cfg.type
        if cfg.findtarget then
            local targets = skill_sys.calc_effect_target(bctx, cfg, self, self,
                self.x, self.y)
            for _, o in pairs(targets) do add(o, id, t_type) end
        else
            add(self, id, t_type)
        end
    end
end

_BG.passive_load = load

function _BG.passive_unload(self, ids)
    if self.passive_effects then
        for _, id in pairs(ids or {}) do
            local cfg = CFG[id]
            del(self, id, cfg.type)
        end
    end
end

function _M.init(self, bctx)
    self.passive_effects = {}
    load(bctx, self, self.passive_list)
end

function _M.destroy(self)
    self.passive_effects = {}
end

require "battle.mods"("passive", _M)

return _M

