--[[
    更改属性
]] local attrlib = require "util.attrs"
local attr_ids = attrlib.ids
local stat = require "battle.stat"
local _BG = require "battle.global"
local passive_type = require "skillsys.passive_type"
local etype = require "skillsys.etype"
local floor = math.floor
local min = math.min
local insert = table.insert
local getsub = require"util.table".getsub
local get_traits_cnt = _BG.get_traits_cnt
local passive_trigger_Bi = _BG.passive_trigger_Bi
local attrcalc = require "skillsys.attrcalc"
local add_p = attrcalc.add_p
local add_a = attrcalc.add_a
local set_p_ex = attrcalc.set_p_ex
local set_a_ex = attrcalc.set_a_ex
local check_show = attrcalc.check_show
local is_type = attrlib.is_type
local stat_push = stat.push
local unpack = table.unpack

local ptype_give_signet<const> = passive_type.give_signet
local ptype_get_signet<const> = passive_type.get_signet
local etype_attr_chg<const> = etype.attr_chg

return function(bctx, src, ctx, tobj, ecfg, e_args, negative_effect)
    local attrs = {}
    local attr_multi = e_args and e_args.attr_multi or 1
    local attr_ex_m = e_args and e_args.attr_ex_m
    local parm = ecfg.parm
    for i = 1, #parm, 3 do
        local _type, attr_id, attr_val = unpack(parm, i, i + 2)
        if _type == 3 then -- 根据伤害计算固定属性
            attr_val = floor(e_args.damage * attr_val / 1000)
            _type = 2
        end
        attr_val = attr_val * attr_multi
        if negative_effect then attr_val = 0 - attr_val end
        local t = getsub(attrs, attr_id)
        t[_type] = (t[_type] or 0) + attr_val
    end

    local parm2 = ecfg.parm2
    if parm2 then -- 根据特性条件计算属性额外加成
        for i = 1, #parm2, 7 do
            local _type, attr_id, base_v, tag_id, tag_v, max_n, num =
                unpack(parm2, i, i + 6)
            local cnt = get_traits_cnt(bctx, src, tag_id, tag_v) - num
            if cnt > 0 then
                cnt = min(max_n, cnt)
                local attr_val = base_v * cnt
                if negative_effect then attr_val = 0 - attr_val end
                local t = getsub(attrs, attr_id)
                t[_type] = (t[_type] or 0) + attr_val
            end
        end
    end

    local _add_p = attr_ex_m and set_p_ex or add_p
    local _add_a = attr_ex_m and set_a_ex or add_a

    local args = {}
    local dirty
    for id, v in pairs(attrs) do
        insert(args, id)
        local key = attr_ids[id]
        local prior_signet = tobj.attrs[key]
        if v[1] then -- 百分比
            _add_p(tobj, key, v[1], attr_ex_m)
        end
        if v[2] then -- 固定值
            _add_a(tobj, key, v[2], attr_ex_m)
        end
        insert(args, (v[1] or 0) + (v[2] or 0))
        if check_show(key) then dirty = true end
        if is_type(id, "signet") then -- 印记变化
            passive_trigger_Bi(bctx, ptype_give_signet, ptype_get_signet, src,
                tobj, ctx, {signet_id = id, prior_signet = prior_signet})
        end
    end
    if dirty then stat_push(bctx, tobj, "battle_attr_chg", tobj) end
    insert(ctx.out, {
        effectid = ecfg.id,
        etype = etype_attr_chg,
        skillid = ctx.skillid,
        caster = src.id,
        target = tobj.id,
        args1 = 0,
        args2 = 0,
        args4 = args
    })
end

