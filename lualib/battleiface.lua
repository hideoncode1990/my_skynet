local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local cfgdata = require "cfg.data"
local uattrs = require "util.attrs"
local uniq = require "uniq.c"

local filter = uattrs.filter

local _M = {}

local CFG, MCFG, CFG_LV

local tag_type
skynet.init(function()
    CFG, MCFG, CFG_LV = cfgproxy("hero", "hero_monster", "hero_level")
    tag_type = cfgdata.basic.condition_hero
end)

local function get_combo(level, skills)
    local skillid
    for i = #skills, 1, -1 do
        if level >= skills[i][1] then
            skillid = skills[i][2]
            break
        end
    end
    return skillid
end

local function skill_list(level, cfg)
    local ret = {cfg.general_skill}
    for _, sub in pairs(cfg.skill) do
        for i = #sub, 1, -1 do
            if level >= sub[i][1] then
                table.insert(ret, sub[i][2])
                break
            end
        end
    end
    return ret
end
local function query_coe(id, level)
    return CFG_LV[level]["stage_" .. MCFG[id].stage]
end

local function get_skill(cfg, level)
    local combo_skill = get_combo(level, cfg.combo or {})
    local skilllist = skill_list(level, cfg)
    return combo_skill, skilllist
end

local function monster_attr(id, level)
    local coe = query_coe(id, level)
    local basic_attrs = filter(MCFG[id])
    local allattrs = uattrs.append({}, basic_attrs)
    local attrs = uattrs.hero_attrs(allattrs, basic_attrs, coe)
    local a = uattrs.for_fight(attrs)
    return a
end

local function add_tag(obj, cfg)
    for _, tag in ipairs(tag_type) do obj[tag] = cfg[tag] end
end

function _M.monster(cfg_monster, attr, attrs_extra, effect)
    local pos, id, level, boss = table.unpack(cfg_monster)
    local add = attr and {atk = attr[1], def = attr[2], hpmax = attr[3]} or {}
    local cfg = MCFG[id]
    local mon = {
        pos = pos,
        id = uniq.id(),
        level = level,
        cfgid = id,
        boss = boss,
        wood = cfg.wood,
        body = cfg.body,
        tab = cfg.tab,
        soulband = cfg.soulband
    }
    add_tag(mon, cfg)
    local attrs = monster_attr(id, level)
    local baseattrs = uattrs.multi_coes(attrs, add)
    if attrs_extra then
        baseattrs = uattrs.append(baseattrs, uattrs.for_fight(attrs_extra))
    end
    mon.baseattrs = baseattrs
    mon.combo_skill, mon.skilllist = get_skill(cfg, level)
    mon.zdl = uattrs.zdl(mon.baseattrs)
    mon.passive_list = effect and (effect[1] ~= 0 and effect) -- 策划用0占位表示没有effct
    return mon
end

function _M.hero(obj, attrs, pos, passive_list)
    local cfgid = obj.id
    local level = obj.level
    local cfg = CFG[cfgid]
    local data = {
        id = obj.uuid,
        cfgid = cfgid,
        level = obj.level,
        tab = cfg.tab,
        soulband = cfg.soulband
    }
    add_tag(data, cfg)
    data.combo_skill, data.skilllist = get_skill(cfg, level)
    data.baseattrs = uattrs.for_fight(attrs)
    data.pos = pos
    data.zdl = uattrs.zdl(data.baseattrs)
    data.passive_list = passive_list
    return data
end

function _M.get_mon_skills(cfgid, level)
    local cfg = MCFG[cfgid]
    local combo_skill, skilllist = get_skill(cfg, level)
    return combo_skill, skilllist
end

local baseattrs = {2, 3, 1} -- 基础属性编号顺序依次为： 攻击（2），防御（3），血（1）

function _M.temphero_attrs(id, level, cfg_attrs, cfg_attrs_extra)
    local attrs = uattrs.filter(CFG[id])
    local coe = query_coe(id, level) -- 等级系数

    for order, attr_id in ipairs(baseattrs) do
        local coe2 = cfg_attrs[order] / 1000 -- 加成
        local val = attrs[attr_id] or 0
        attrs[attr_id] = val * coe * coe2
    end

    for attr_id, val in pairs(cfg_attrs_extra or {}) do
        attrs[attr_id] = (attrs[attr_id] or 0) + val
    end
    return attrs
end

function _M.mon_zdl(id, level, attr, attrs_extra)
    local add = attr and {atk = attr[1], def = attr[2], hpmax = attr[3]} or {}
    local attrs = monster_attr(id, level)
    local battrs = uattrs.multi_coes(attrs, add)
    if attrs_extra then
        battrs = uattrs.append(battrs, uattrs.for_fight(attrs_extra))
    end
    return uattrs.zdl(battrs)
end

function _M.hero_star(cfgid)
    local cfg = CFG[cfgid]
    return cfg.star
end
return _M
