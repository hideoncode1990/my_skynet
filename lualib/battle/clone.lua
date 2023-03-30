local attrcalc = require "skillsys.attrcalc"
local stat = require "battle.stat"
local uattrs = require "util.attrs"
local b_util = require "battle.util"
local utable = require "util.table"
local heroclass = require "battle.class.hero"
local object = require "battle.object"
local _M = {}

local function add(bctx, master, obj, ctx, eid, maxnum)
    local clones = utable.getsub(master, "clones")
    table.insert(clones, obj)
    local cnt = 0
    -- 限制不同召唤方式可召唤的数量
    for i = #clones, 1, -1 do
        local o = clones[i]
        if o.from_eid == eid then
            if cnt >= maxnum then
                table.remove(clones, i)
                object.set_dead(bctx, o, master, ctx, true, "clone max")
            else
                cnt = cnt + 1
            end
        end
    end
end

local function create(bctx, master, ctx, args)
    local id = b_util.genid(bctx)
    local obj = {
        id = id,
        x = args.x,
        y = args.y,
        masterid = master.id,
        cfgid = args.cfgid,
        level = master.level,
        ave_level = master.ave_level,
        combo_skill = args.combo_skill,
        skilllist = args.skilllist,
        init_buffs = args.init_buffs,
        from_eid = args.from_eid,
        clonetype = args.clonetype
    }
    attrcalc.copy(obj, master, args.attrs_coe)
    b_util.inherit_tag(obj, master)
    add(bctx, master, obj, ctx, args.from_eid, args.maxnum)
    attrcalc.add_a(master, "clone_hurtup", args.clone_hurtup)
    obj.zdl = uattrs.zdl(obj.baseattrs)
    return obj
end

function _M.sacrifice(bctx, master, ctx)
    local clones
    clones, master.clones = master.clones, nil
    if not clones or not next(clones) then return end
    for _, o in ipairs(clones) do
        object.set_dead(bctx, o, master, ctx, true, "sacrifice")
    end
end

function _M.remove(master, id)
    local clones = master.clones
    if clones then
        for i, o in ipairs(clones) do
            if o.id == id then
                table.remove(clones, i)
                break
            end
        end
    end
end

return setmetatable(_M, {
    __call = function(_, bctx, master, ...)
        local self = create(bctx, master, ...)
        return heroclass.init(bctx, self, master.camp, nil, self.ave_level)
    end
})
