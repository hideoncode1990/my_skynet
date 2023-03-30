local skynet = require "skynet"
local lfs = require "lfs"
local env = require "env"
local log = require "log"
local _M = {}
local E = {}
local fight_costmax, delaymax = 0, 0
local total_fightcost, fightcost_now, high_fightcost_now = 0, 0, 0
local total_delay, delay_now, high_delay_now = 0, 0, 0
local CNT, now_cnt = 0, 0

local max = math.max

local CALLS = {}
skynet.init(function()
    local path = string.format("%s/lualib/battle/profile/fmt", env.root)
    for file in lfs.dir(path) do
        if file ~= "." and file ~= ".." then
            local pos = string.find(file, ".lua$")
            if pos then
                local name = string.sub(file, 1, pos - 1)
                local m = require(string.format("battle.profile.fmt.%s", name))
                CALLS[name] = m
            end
        end
    end
end)

function _M.init(self)
    self.profile_data = {total_cost = 0, uuid = self.uuid}
end

local function get(self, k)
    local pf = self.profile_data
    return pf[k]
end

local function set(bctx, self, k, v)
    local pf = self.profile_data
    pf[k] = v
end

local function add(bctx, self, k, v)
    local pf = self.profile_data
    local o_val = pf[k] or 0
    pf[k] = o_val + v
end

function _M.print(self, bctx)
    -- local s_base = CALLS.base(bctx, self)
    -- local s_fsm = CALLS.fsm(bctx, self)
    -- local s_cast = CALLS.cast(bctx, self)
    -- local s_fsmidle = CALLS.fsmidle(bctx, self)
    -- local s_buff = CALLS.buff(bctx, self)

    -- local s = string.format("%s %s", s_base, s_buff)
    -- log(s)
end

local function _log(nm, bctx, id, ...)

end

function _M.log(nm)
    return function(bctx, id, ...)
        _log(nm, bctx, id, ...)
    end
end

function _M.destroy(self, bctx)
    _M.print(self, bctx)
end

function _M.dump(self)
    local pf = self.profile_data
    pf.E = E
    ldump(pf, "profile data " .. (self.id or self.uuid))
    E = {}
end

function _M.show_allobjs_hex(bctx)
    local objmgr = bctx.objmgr
    local objs = objmgr.get_all()
    local t = {}
    for _, o in pairs(objs) do
        table.insert(t, string.format("[%s:%d,%d]", o.id, o.hex.hx, o.hex.hy))
    end
    local s = table.concat(t, ",")
    log(s)
end

function _M.result(bctx)
    local data = bctx.profile_data
    if data then
        CNT = CNT + 1
        now_cnt = now_cnt + 1
        local fightcost = data.fight_cost or 0
        if fightcost > fight_costmax then fight_costmax = fightcost end
        if fightcost > high_fightcost_now then
            high_fightcost_now = fightcost
        end
        total_fightcost = total_fightcost + fightcost
        fightcost_now = fightcost_now + fightcost

        local delay = data.max_delay or 0
        if delay > delaymax then delaymax = delay end
        if delay > high_delay_now then high_delay_now = delay end
        total_delay = total_delay + delay
        delay_now = delay_now + delay
    end
end

function _M.check_maxcost(time)
    return (time or 0) > fight_costmax
end

function _M.monitor_info()
    local cnt, delay, fightcost, hight_delay, high_fightcost = now_cnt,
        delay_now, fightcost_now, high_delay_now, high_fightcost_now
    now_cnt, delay_now, fightcost_now, high_delay_now, high_fightcost_now = 0,
        0, 0, 0, 0

    local real_delay, real_fightcost = 0, 0
    if cnt > 0 then real_delay, real_fightcost = delay / cnt, fightcost / cnt end

    local ave_delay, ave_fightcost = 0, 0
    if CNT > 0 then
        ave_delay, ave_fightcost = total_delay / CNT, total_fightcost / CNT
    end
    return {
        total = CNT,
        delaymax = delaymax,
        ave_delay = ave_delay,
        real_delay = real_delay,
        high_delay = hight_delay,
        fightcostmax = fight_costmax,
        ave_fightcost = ave_fightcost,
        real_fightcost = real_fightcost,
        high_fightcost = high_fightcost
    }
end

function _M.addtable(bctx, self, tname, k, v)
    local pf = self.profile_data
    local t = pf[tname]
    if not t then
        t = {}
        pf[tname] = t
    end
    local o_val = t[k] or 0
    t[k] = o_val + v
end

function _M.addlist(bctx, self, lname, v)
    local pf = self.profile_data
    local list = pf[lname]
    if not list then
        list = {}
        pf[lname] = list
    end
    table.insert(list, v)
end

function _M.settable(bctx, self, tname, k, v)
    local pf = self.profile_data
    local t = pf[tname]
    if not t then
        t = {}
        pf[tname] = t
    end
    t[k] = v
end

function _M.add_E(k, v)
    E[k] = (E[k] or 0) + v
end

_M.add = add
_M.set = set
_M.get = get

require "battle.mods"("profile", _M)
return _M
