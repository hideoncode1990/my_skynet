local skynet = require "skynet"
local utime = require "util.time"
local client = require "client.mods"
local cfgproxy = require "cfg.proxy"
local award = require "role.award"
local uaward = require "util.award"
local variable = require "variable"
local flowlog = require "flowlog"
local platlog = require "platlog"
local fnopen = require "role.fnopen"
local task = require "task"
local cache = require("mongo.role")("recruits")
local schema = require "mongo.schema"
local utable = require "util.table"
local hinit = require "hero"

local _H = require "handler.client"
local _LUA = require "handler.lua"

cache.schema(schema.NOBJ(schema.OBJ({
    type = schema.ORI, -- 类型
    update = schema.ORI, -- 每日次数更新时的时间戳
    features = schema.NOBJ(), -- SPECIAL类型当日购买的featrue
    one = schema.ORI, -- 单抽每日累计次数
    ten = schema.ORI, -- 十抽每日累计次数
    total = schema.ORI, -- 单抽和十抽抽取总次数，不重置
    extra = schema.ORI, -- 额外奖励余留次数
    failure = schema.ORI -- 失败次数
})))

local SPECIAL<const>, NM<const> = 2, "recruit"

local BASIC, CFG, CFG_ACT, RECRUITD, RECRUIT_ACTD, RUNNING
local enter
skynet.init(function()
    RECRUITD = skynet.uniqueservice("game/recruitd")
    RECRUIT_ACTD = skynet.uniqueservice("game/recruit_actd")
    BASIC, CFG, CFG_ACT = cfgproxy("basic", "recruit", "activity_recruit")
    fnopen.reg(NM, NM, enter)
end)

local function check_daily_cnt(self, d, now)
    if not utime.same_day(now, (d.update or 0), BASIC.recruit_refresh) then
        d.update = now
        d.one = nil
        d.ten = nil
        cache.dirty(self)
    end
    return d
end

local function get_data(self, tp)
    local C = cache.get(self)
    local d = C[tp]
    local now = utime.time_int()
    if not d then
        d = {type = tp, update = now}
        C[tp] = d
    else
        d = check_daily_cnt(self, d, now)
    end
    return d
end

local function get_cfg(_, tp)
    local cfg = CFG[tp]
    local open = cfg.permanent or RUNNING[tp]
    return open and cfg
end

local function check_bought_features(self, d, now)
    local features = d.features
    if features then
        for feature, time in pairs(features) do
            if not utime.same_day(now, time, BASIC.switch_time) then
                features[feature] = nil
                cache.dirty(self)
            end
        end
        if not next(features) then
            features = nil
            d.features = features
            cache.dirty(self)
        end
    end
    return features
end

local function calc_default_feature(_, now)
    local features = BASIC.switch_features
    local begin = utime.begin_day(variable.server_starttime, BASIC.switch_time)
    local order = ((now - begin) // 86400) % #features + 1
    return features[order]
end

local function get_running()
    local running, forbidden = skynet.call(RECRUIT_ACTD, "lua",
        "recruit_actd_info")
    for tp in pairs(forbidden) do running[tp] = nil end
    RUNNING = running
end

local function push_info(self)
    local now = utime.time_int()
    local permanent, act, temp = {}, {}, {}
    local info = {
        check_time = now,
        default = calc_default_feature(self, now),
        permanent = permanent,
        act = act
    }

    for tp, d in pairs(cache.get(self)) do
        check_daily_cnt(self, d, now)
        if tp == SPECIAL then
            info.features = check_bought_features(self, d, now)
        end

        if CFG[tp].permanent then
            table.insert(permanent, d)
        elseif RUNNING[tp] then
            table.insert(act, d)
            temp[tp] = true
        end
    end
    for tp in pairs(RUNNING) do
        if not temp[tp] then table.insert(act, get_data(self, tp)) end
    end
    client.enter(self, NM, "recruit_info", info)
end

enter = function(self)
    if fnopen.check_open(self, NM) then
        get_running()
        push_info(self)
    end
end

require("role.mods") {
    name = "recruit",
    load = function(self)
        local now = utime.time_int()
        local C = cache.get(self)
        local change
        for tp in pairs(C) do
            local cfg, cfg_act = CFG[tp], CFG_ACT[tp]
            if not cfg or
                (not cfg.permanent and (not cfg_act or now >= cfg_act.overti)) then
                C[tp] = nil
                change = true
            end
        end
        if change then cache.dirty(self) end
    end,
    enter = enter
}

local function check_feature(self, d, feature, now)
    if calc_default_feature(self, now) == feature then
        return true
    else
        local features = check_bought_features(self, d, now)
        return features and features[feature]
    end
end

local function check_cost(self, costs)
    for _, c in ipairs(costs) do
        local cost = {c}
        if award.checkdel(self, cost) then return cost end
    end
    return false
end

local function draw(self, msg, mark, size)
    if not fnopen.check_open(self, NM) then return {e = 1} end

    local now = utime.time_int()
    local tp, feature = msg.type, msg.feature

    local cfg = get_cfg(self, tp)
    if not cfg then return {e = 4} end

    local d = get_data(self, tp)
    if tp == SPECIAL and not check_feature(self, d, feature, now) then
        return {e = 2}
    end

    feature = tp ~= SPECIAL and 0 or feature
    local _total = d.total or 0
    local total, items, failure, extra, extra_reward =
        skynet.call(RECRUITD, "lua", "draw", tp, mark, size, _total, feature,
            d.extra, d.failure or 0)
    -- call回来后再检查
    if total ~= _total + size then return {e = 8} end -- 重复点击

    local limit, cnt = cfg["limit_" .. mark], d[mark] or 0
    if limit and limit <= cnt then return {e = 3} end

    local reward = cfg[mark .. "_reward"]
    local costs = cfg[mark .. "_price"]
    local cost = check_cost(self, costs)
    if not cost then return {e = 5} end

    local option = {flag = NM .. mark, arg1 = tp, arg2 = feature}
    local adds = uaward(extra_reward).append_one(reward).insert(items)
    local adds_result = adds.result
    local ok, err = award.checkadd(self, adds_result)
    if not ok then return {e = err} end

    local newtab = hinit.check_new_tab(self, items)
    assert(award.deladd(self, option, cost, adds_result))

    if limit then d[mark] = cnt + 1 end
    d.total = total
    d.extra = extra
    d.failure = failure
    cache.dirty(self)

    local tasktype = cfg.tasktype
    if tasktype then task.trigger(self, tasktype, size) end
    flowlog.role_act(self, option)
    if not cfg.permanent then
        platlog("activity", {activity_id = "recruit", sub_id = mark}, self)
    end
    return {e = 0, reward = adds.pack(), extra = extra, newtab = newtab}
end

function _H.recruit_one(self, msg)
    return draw(self, msg, "one", 1)
end

function _H.recruit_ten(self, msg)
    return draw(self, msg, "ten", 10)
end

local function find_feature(feature)
    for _, v in ipairs(BASIC.switch_features) do
        if feature == v then return true end
    end
    return false
end

function _H.recruit_buy(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end

    local feature = assert(msg.feature)
    assert(find_feature(feature))

    local d = get_data(self, SPECIAL)
    local now = utime.time_int()
    if check_feature(self, d, feature, now) then return {e = 2} end

    local option = {flag = "recruit_buy", arg1 = feature}
    local ok, err = award.del(self, option, {BASIC.switch_consume})
    if not ok then return {e = err} end

    local data = utable.sub(d, "features")
    data[feature] = now
    cache.dirty(self)
    flowlog.role_act(self, option)
    return {e = 0, time = now}
end

local function act_open(self, tp, time)
    assert(not RUNNING[tp])
    RUNNING[tp] = time
    client.push(self, NM, "recruit_act_open",
        {time = time, act = get_data(self, tp)})
end

_LUA.recruit_act_open = act_open
_LUA.recruit_act_recover = act_open

local function act_over(self, tp, need_del)
    assert(RUNNING[tp])
    RUNNING[tp] = nil
    if need_del then
        cache.get(self)[tp] = nil
        cache.dirty(self)
    end
    client.push(self, NM, "recruit_act_over", {type = tp})
end

function _LUA.recruit_act_over(self, tp)
    act_over(self, tp, true)
end

function _LUA.recruit_act_forbidden(self, tp)
    act_over(self, tp)
end
