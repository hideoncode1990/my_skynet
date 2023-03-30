local camp_type = require "battle.camp_type"
local objtype = require "battle.objtype"
local _BG = require "battle.global"

function _BG.hero_dead(bctx, obj)
    bctx.objs.dead(obj)
end

local b_util = require "battle.util"
local ulog = b_util.log
local function log(bctx, self, ...)
    ulog(bctx, ...)
end

return function(CBS)
    local inc_cnt = CBS.inc_cnt
    local dec_cnt = CBS.dec_cnt
    local BCTX = CBS.bctx

    local list = {}
    local CNTS = {[camp_type.left] = 0, [camp_type.right] = 0}

    local function inc(o)
        if o.objtype == objtype.hero then
            local camp = o.camp
            local cnt = CNTS[camp]
            cnt = cnt + 1
            CNTS[camp] = cnt
            inc_cnt(BCTX, camp, cnt)
        end
    end

    local function dec(o)
        if o.objtype == objtype.hero then
            local camp = o.camp
            local cnt = CNTS[camp]
            cnt = cnt - 1
            CNTS[camp] = cnt
            dec_cnt(BCTX, camp, cnt)
        end
    end

    local function clean()
        for i = #list, 1, -1 do
            local o = list[i]
            if not o.__valid__ then table.remove(list, i) end
        end
    end

    local idx, len
    local meta = {
        __index = function(t, k)
            error("obj_list cannot support index")
        end,
        __newindex = function(t, k, v)
            error("obj_list cannot support newindex")
        end,
        __pairs = function(t)
            local i, n = idx or 0, len or #list
            len = n
            local mark
            local now = BCTX.btime.now
            local function next()
                i = i + 1
                local o
                if i <= n then
                    o = list[i]
                    local valid = o.__valid__
                    local next_up_ti = o.next_up_ti or now
                    if not valid or now < next_up_ti then
                        --[[
                        log(BCTX, o,
                            "%s objlist fail valid:%s next_up_ti:%.2f %d", o.id,
                            tostring(valid), next_up_ti,
                            math.ceil(next_up_ti / 20))
                        -- ]]
                        if not valid then mark = true end
                        return next()
                    end
                    idx = i
                    return i, o
                end
                if mark then clean() end
                idx, len = nil, nil
                return nil, nil
            end
            return next
        end
    }

    local function add(o)
        table.insert(list, o)
        inc(o)
    end

    local function get_cnt(camp)
        return CNTS[camp]
    end

    local function dead(obj)
        for _, o in ipairs(list) do
            if o.id == obj.id then
                dec(o)
                break
            end
        end
    end

    return setmetatable({add = add, get_cnt = get_cnt, dead = dead}, meta)
end
