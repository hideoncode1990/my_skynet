local skynet = require "skynet"
local utime = require "util.time"
local client = require "client.mods"
local awardtype = require "role.award.type"
local cache = require("mongo.role")("mainline")
local award = require "role.award"
local utable = require "util.table"
local m_battle = require "role.m_battle"
local battle = require "battle"
local cfgproxy = require "cfg.proxy"
local drop = require "role.drop"
local flowlog = require "flowlog"
local m_friend = require "role.m_friend"
local roleinfo = require "roleinfo.change"
local condition = require "role.condition"
local ctype = require "role.condition.type"
local event = require "role.event"
local uaward = require "util.award"
local guild = require "guild"
local addition = require "role.addition"
local task = require "task"
local hinit = require "hero"
local platlog = require "platlog"
local mainline_code = require "platlog.code.mainline"
local battleiface = require "battleiface"
local email = require "email"
local lang = require "lang"
local utrans = require "util.trans"
local LOCK = require("skynet.queue")()

local _H = require "handler.client"
local _M = {}

local floor = math.floor
local insert = table.insert

local NM<const> = "mainline"
local CFG, CFG_INDEX, CFG_TPS, BASIC, SUPPORT, GUIDE

local mainlined

skynet.init(function()
    CFG, CFG_INDEX, CFG_TPS, BASIC, SUPPORT, GUIDE =
        cfgproxy("mainline", "mainline_index", "mainline_tps", "basic",
            "support", "guide_guides")
    mainlined = skynet.uniqueservice("game/mainlined")
end)

local function get_support(self, C)
    local now = utime.time()
    if not utime.same_day(now, (C.support_update or 0)) then
        C.support = 0
        C.support_update = now
        cache.dirty(self)
    end
    return C.support
end

local function enter_push(self)
    local C = cache.get(self)
    client.enter(self, NM, "mainline_info",
        {update = C.update, id = C.id, support = get_support(self, C)})
end

-- C.id 表示已经通过的最大关卡id。如通了1004，未通1005，则C.id=1004
-- 算挂机的reward时，要用下一关的配置算，如C.id=0时，用1001的配置，最后一关用本身配置
local function query_CFG(_, C)
    if C.id == 0 then return CFG_INDEX[1] end -- 最初没有任何通关，直接读index为1的配置。为特殊处理
    local cfg = CFG[C.id]
    local cfg_next = CFG_INDEX[cfg.index + 1]
    -- 没有cfg_next 表示C.id 是最后一关，用cfg替代cfg_next,为特殊处理
    if cfg_next then
        return cfg_next
    else
        return cfg, true
    end
end

require("role.mods") {
    name = NM,
    load = function(self)
        local C = cache.get(self)
        local now = utime.time()

        if not C.id then
            C.id = 0 -- 初始化成0 表示未通关任何关卡
            local cfg = query_CFG(self, C)
            for _nm in pairs(CFG_TPS) do
                local arg = cfg[_nm]
                local common_update = utable.sub(C, "common_update")
                if arg and not common_update[_nm] then
                    common_update[_nm] = now
                end
            end
            C.update = now
            C.helptime = addition.sum(self, "helptime")
            C.expire = C.update + BASIC.mainline_maxtime + C.helptime
            cache.dirty(self)
        end
        self.mainline = C.id
        roleinfo.change(self, "mainline", C.id)

        -- 以下为兼容代码
        if not C.update then
            C.update = now
            cache.dirty(self)
        end
        if not C.helptime then
            C.helptime = addition.sum(self, "helptime")
            cache.dirty(self)
        end
        if not C.expire then
            C.expire = C.update + BASIC.mainline_maxtime + C.helptime
            cache.dirty(self)
        end
    end,
    enter = enter_push
}

-- 在更新了C.update或addition变化时，修正每种奖励的inner_update
local function amend_inner_update(self, C, now)
    local expire = C.expire
    local cfg = query_CFG(self, C)
    -- 当结算时的时间点now 大于expire时，超出部分不会计算掉落，但下次掉落时间起点直接为设置为now，然后做微调
    if now >= expire then
        -- common 普通奖励 --extra 额外奖励
        local common_update = utable.sub(C, "common_update")
        for _nm, time in pairs(common_update) do
            -- need_save 是不能被单位时间整除的时长
            local need_save = expire - time
            -- 在now时间点往前调need_save的时长，就相当于把这段没有产出的时间拼接到下次来计算
            common_update[_nm] = now - need_save
        end

        -- extra 额外奖励
        if cfg.drop then -- 如果该层主线的配置需要产生额外掉落
            if C.extra_update then
                local need_save = expire - C.extra_update
                C.extra_update = now - need_save
            end
        else
            C.extra_update = now -- 如果不需要掉落，不需要拼接，直接更新到now
        end

        -- special 特殊奖励
        if cfg.special_drop then
            if C.special_update then
                -- 由于特殊奖励添加了内置CD，need_save可能为负数，
                -- 则now - need_save相当于后调，而后调相当于把没有经历完的内置CD 继承到了下一次。
                -- 但是，根据策划要求，这部分不用继承，自然时间抵扣，所以有以下处理
                local need_save = expire - C.special_update
                if need_save < 0 then
                    C.special_update = math.max(now, C.special_update)
                else
                    C.special_update = now - need_save
                end
            end
        else
            C.special_update = now
        end
    else
        if not cfg.drop and C.extra_update then C.extra_update = now end
        if not cfg.special_drop and C.special_update then
            C.special_update = math.max(now, C.special_update)
        end
    end
end

local function calc(_, expire, now, inner_update, unit_cnt, unit_time)
    if inner_update >= expire then return end
    if now <= inner_update then return end
    local last
    if now <= expire then
        last = now - inner_update
    else
        last = expire - inner_update
    end
    local cnt = floor(last // unit_time)
    if cnt > 0 then
        local sum_cnt = floor(cnt * unit_cnt)
        if sum_cnt > 0 then
            inner_update = inner_update + unit_time / unit_cnt * sum_cnt
            return inner_update, sum_cnt
        end
    end
end

-- common 普通奖励 --extra 额外奖励 --special 特殊奖励

local function calc_common(self, C, now, reward, cfg)
    local common_tbl, dirty = utable.sub(C, "common_update")
    local expire = C.expire
    for _nm, conf in pairs(CFG_TPS) do
        local arg = cfg[_nm]
        if arg then
            local common_update, cnt = common_tbl[_nm] or C.update, nil
            common_update, cnt = calc(self, expire, now, common_update, arg[1],
                arg[2])
            if cnt then
                dirty = true
                common_tbl[_nm] = common_update
                uaward(reward).append_one({conf[1], conf[2] or 0, cnt})
            end
        end
    end
    if dirty then cache.dirty(self) end
end

local function calc_extra(self, C, now, reward, cfg)
    local cfg_drop = cfg.drop
    if not cfg_drop then return end

    local extra_update, cnt = C.extra_update or C.update, nil
    local dropid, unit_time = cfg_drop[1], cfg_drop[2]
    extra_update, cnt = calc(self, C.expire, now, extra_update, 1, unit_time)
    if cnt then
        uaward(reward).append(drop.calc(dropid, cnt))
        C.extra_update = extra_update
        cache.dirty(self)
    end
end

local function calc_special(self, C, now, reward, cfg)
    local spcfg = cfg.special_drop
    if not spcfg then return end

    local expire = C.expire
    local special_update = C.special_update or C.update

    if special_update >= expire then return end
    if now <= special_update then return end

    local last
    if now <= expire then
        last = now - special_update
    else
        last = expire - special_update
    end

    local dropid, unit_time, rate, cd_time = spcfg[1], spcfg[2], spcfg[3],
        spcfg[4] or 0
    assert(unit_time > 0)

    local change
    while last > 0 do
        last = last - unit_time -- 剩余时间如果能包含一个unit_time,就做一次逻辑
        if last >= 0 then
            special_update = special_update + unit_time
            change = true

            local special_rate = C.special_rate or 0
            if rate + special_rate >= math.random(1, 1000) then
                C.special_rate = 0
                uaward(reward).append(drop.calc(dropid))
                -- 如果成功发生掉落，就还要添加一段内置CD 这段时间内没有掉落
                -- 加了内置CD之后，special_update有可能大于expire
                special_update = special_update + cd_time
                last = last - cd_time
            else
                C.special_rate = special_rate + rate
            end
        else
            break
        end
    end
    if change then
        C.special_update = special_update
        cache.dirty(self)
    end
end

local atype = {
    [awardtype.gold] = "coinadd",
    [awardtype.exp] = "expadd",
    [awardtype.essence] = "syncadd",
    [awardtype.fragment] = "chipadd",
    [awardtype.items] = "itemadd"
}
-- reward中，同类型不重复
local function addition_reward(_, C, reward)
    local reward_add = {}
    for _, v in ipairs(reward) do
        local coe, more
        local tp, id, cnt = v[1], v[2], v[3]
        local k = atype[tp]
        if k then coe = C[k] end

        if coe then
            more = floor(cnt * coe / 1000)
            if more > 0 then insert(reward_add, {tp, id, more}) end
        end
    end
    return reward_add
end

local function sum_reward(_, C, reward, reward_add)
    uaward(utable.sub(C, "reward")).append(reward)
    uaward(utable.sub(C, "reward_add")).append(reward_add)
end

local function calc_reward_inner(self, C, now)
    local cfg = query_CFG(self, C)
    local reward = {}

    calc_common(self, C, now, reward, cfg)
    calc_extra(self, C, now, reward, cfg)
    calc_special(self, C, now, reward, cfg)

    local reward_add = addition_reward(self, C, reward)

    sum_reward(self, C, reward, reward_add)
    C.opttime = now
    cache.dirty(self)

end

local function calc_reward(self, C, now)
    LOCK(calc_reward_inner, self, C, now)
end

function _H.mainline_show_reward(self)
    local C = cache.get(self)
    calc_reward(self, C, utime.time())
    return {
        e = 0,
        reward = uaward.pack(C.reward),
        reward_add = uaward.pack(C.reward_add)
    }
end

local function calc_task_gold(_, reward)
    local tp, sum = awardtype.gold, 0
    for _, v in ipairs(reward) do if v[1] == tp then sum = sum + v[3] end end
    return sum
end

local function mainline_get_reward(self)
    local now = utime.time()
    local C = cache.get(self)
    -- 领取时间戳必须大于等于calc_reward的时间戳
    -- 否则返回错误码，保证数据自洽 （调时间再恢复可能出现）
    local opttime = C.opttime or now
    if now < opttime then return {e = 1} end

    calc_reward(self, C, now)

    local reward, reward_add = C.reward, C.reward_add
    if next(reward) then
        amend_inner_update(self, C, now)

        C.update = now
        C.expire = C.update + BASIC.mainline_maxtime + C.helptime
        C.reward = {}
        C.reward_add = {}
        cache.dirty(self)

        local reward_sum = {}
        uaward(reward_sum).append(reward).append(reward_add)
        award.adde(self, {
            flag = "mainline_get_reward",
            arg1 = C.id,
            theme = "MAINLINE_REWARD_FULL_THEME_",
            content = "MAINLINE_REWARD_FULL_CONTENT_"
        }, reward_sum)

        task.trigger(self, "ml_reward")
        task.trigger(self, "ml_gold", calc_task_gold(self, reward_sum))

        flowlog.role_act(self, {flag = "mainline_get_reward", arg1 = C.id})
    end
    return {
        e = 0,
        update = now,
        reward = uaward.pack(reward),
        reward_add = uaward.pack(reward_add)
    }
end

function _H.mainline_get_reward(self)
    return LOCK(mainline_get_reward, self)
end

local function check_reward_open(self, C, cfg)
    local common_update = utable.sub(C, "common_update")
    local dirty
    for _nm in pairs(CFG_TPS) do
        local arg = cfg[_nm]
        if arg and not common_update[_nm] then
            common_update[_nm] = utime.time()
            dirty = true
        end
    end
    if dirty then cache.dirty(self) end
end

local function calc_reward_special_win(self, C)
    local cfg = query_CFG(self, C)
    local cfg_special = cfg.special_win
    if not cfg_special then return end

    local dropid, rate = cfg_special[1], cfg_special[2]
    if rate >= math.random(1, 1000) then
        C.special_rate = 0
        local reward = drop.calc(dropid)
        local reward_add = addition_reward(self, C, reward)
        sum_reward(self, C, reward, reward_add)
    else
        C.special_rate = (C.special_rate or 0) + cfg.special_drop[3]
    end
    cache.dirty(self)
end

local function change(self, tar_id, option)
    local C = cache.get(self)
    -- 用老的关卡id 将挂机的reward 算一遍，新关卡有新产出速率
    calc_reward(self, C, utime.time())
    calc_reward_special_win(self, C)
    C.id = tar_id
    cache.dirty(self)

    self.mainline = tar_id
    roleinfo.change(self, "mainline", tar_id)

    local cfg = query_CFG(self, C)
    check_reward_open(self, C, cfg)
    event.occur("EV_MAINLINE", self, tar_id)
    client.push(self, NM, "mainline_win", {id = tar_id})
    task.trigger(self, "ml_id", tar_id)
    task.trigger(self, "ml_chapter", tar_id)
    flowlog.role(self, "mainline", {
        flag = option.flag,
        arg1 = option.arg1,
        arg2 = option.arg2,
        tarid = tar_id
    })
end

local function lineup_zdl(_, list)
    local sum = 0
    for _, info in pairs(list) do sum = info.zdl + sum end
    return sum
end

function _H.mainline_fight(self, msg)
    local C = cache.get(self)
    local tar_cfg, islast = query_CFG(self, C)
    if islast then return {e = 1} end

    local bi = msg.battle_info
    local tar_id = tar_cfg.id
    local cfg_guide = GUIDE[tar_id]
    bi.multi_speed = cfg_guide and cfg_guide.multi_speed or bi.multi_speed
    local list, list_save = m_battle.check_bi(self, bi)
    if not list then return {e = list_save} end

    local left, err = m_battle.create_heroes(self, list)
    if not left then return {e = err} end

    if tar_cfg.effect then insert(left.passive_list, tar_cfg.effect) end
    local save
    if tar_cfg.video then save = true end

    local right = m_battle.create_monsters(tar_cfg.monster)

    local ctx<close> = battle.create(NM, tar_cfg.mapid, {
        auto = bi.auto,
        multi_speed = cfg_guide and cfg_guide.multi_speed or bi.multi_speed,
        skip = bi.skip,
        no_play = bi.no_play,
        save = save
    }, cfg_guide and cfg_guide.limit)

    if not battle.join(ctx, self) then return {e = 106} end

    if not tar_cfg.guide_save then m_battle.set_lineup(self, NM, list_save) end

    local ids, power, stars = {}, {}, {}
    for _, o in ipairs(left.heroes) do
        local cfgid = o.cfgid
        table.insert(ids, cfgid)
        table.insert(power, o.zdl)
        table.insert(stars, battleiface.hero_star(cfgid))
    end
    local ids_s = table.concat(ids, "|")
    local power_s = table.concat(power, "|")
    local stars_s = table.concat(stars, "|")

    local flag<const> = "mainline_win"
    local win
    battle.start(ctx, left, right, function(ok, ret)
        if not ok then return battle.abnormal_push(self) end
        if ret.restart or ret.terminate then
            return battle.push(self, ret)
        end

        task.trigger(self, "ml_fight")
        win = ret.win
        local reward, newtab
        if win == 1 then
            change(self, tar_id, {flag = flag})
            reward = tar_cfg.win

            newtab = hinit.check_new_tab(self, reward)
            award.adde(self, {
                flag = flag,
                arg1 = tar_id,
                theme = "MAINLINE_BATTLE_FULL_THEME_",
                content = "MAINLINE_BATTLE_FULL_CONTENT_"
            }, reward)

            local eaward = tar_cfg.email
            if eaward then
                email.send({
                    target = self.rid,
                    theme = lang("MAINLINE_WIN_THEME_{1}",
                        utrans.mainline(tar_id)),
                    content = lang("MAINLINE_WIN_CONTENT"),
                    items = eaward,
                    option = {flag = flag, arg1 = tar_id}
                })
            end

            if save then
                skynet.send(mainlined, "lua", "add", self.rid, tar_id,
                    lineup_zdl(self, list), ret.report)
            end
        end

        platlog("mainline", {
            step_num_id = mainline_code.finish,
            mainline_id = tar_id,
            degree = 0,
            hero_ids = ids_s,
            hero_power = power_s,
            hero_stars = stars_s,
            fight_time = ret.totaltime,
            result = win
        }, self)

        client.push(self, NM, "mainline_result", {
            id = C.id,
            endinfo = battle.battle_endinfo(ret, reward),
            newtab = newtab
        })

        if tar_cfg.guide_save then
            m_battle.set_lineup(self, NM, list_save)
        end
    end)
    flowlog.role_act(self, {flag = "mainline_fight", arg1 = tar_id})
    platlog("mainline", {
        step_num_id = mainline_code.start,
        mainline_id = tar_id,
        degree = 0,
        hero_ids = ids_s,
        hero_power = power_s,
        hero_stars = stars_s,
        fight_time = 0,
        result = 1
    }, self)
    return {e = 0}
end

function _H.mainline_support(self)
    local C = cache.get(self)
    local support = get_support(self, C)
    if support >= addition.sum(self, "addtimes") then return {e = 1} end

    local this_support = support + 1
    local option = {
        flag = "mainline_support",
        arg1 = this_support,
        theme = "MAINLINE_SUPPORT_FULL_THEME_",
        content = "MAINLINE_SUPPORT_FULL_CONTENT_"

    }
    local pay = SUPPORT[this_support].pay
    if pay and not award.del(self, option, {pay}) then return {e = 2} end

    C.support = this_support
    cache.dirty(self)

    local reward = {}
    local long = BASIC.time_support
    local cfg = query_CFG(self, C)
    for _nm, conf in pairs(CFG_TPS) do
        local arg = cfg[_nm]
        if arg and conf[1] ~= awardtype.rexp then
            local num = floor(long / arg[2] * arg[1])
            table.insert(reward, {conf[1], conf[2] or 0, num})
        end
    end

    local cfg_drop = cfg.drop
    local cnt = floor(long / cfg_drop[2])
    if cnt > 0 then uaward(reward).append(drop.calc(cfg_drop[1], cnt)) end
    local reward_add = addition_reward(self, C, reward)

    local reward_sum = uaward().append(reward).append(reward_add).result

    award.adde(self, option, reward_sum)

    task.trigger(self, "ml_support")
    task.trigger(self, "ml_gold", calc_task_gold(self, reward_sum))
    flowlog.role_act(self, {flag = "mainline_support", arg1 = this_support})
    return {
        e = 0,
        support = C.support,
        reward = uaward.pack(reward),
        reward_add = uaward.pack(reward_add)
    }
end

function _H.mainline_replay(self, msg)
    local id = msg.id
    if not CFG[id].video then return {e = 1} end

    local final = skynet.call(mainlined, "lua", "replay", self.rid, msg.id,
        m_friend.flist_get(self), guild.get_members(self), BASIC.replay_friend,
        BASIC.replay_guild, BASIC.replay_max)

    return {e = 0, list = final}
end

function _M.itemuse(self, usepara, cnt)
    local reward = {}
    local C = cache.get(self)
    for _, v in ipairs(usepara) do
        local tp, id, last = v[1], v[2], v[3]
        local cfg = query_CFG(self, C)
        for _nm, conf in pairs(CFG_TPS) do
            if tp == conf[1] and id == (conf[2] or 0) then
                local arg = cfg[_nm]
                if not arg then return false end
                local num = last / arg[2]
                table.insert(reward, {tp, id, floor(cnt * num * arg[1])})
            end
        end
    end
    return reward
end

function _M.change(self, tar_id, option)
    if not CFG[tar_id] then return false end
    change(self, tar_id, option)
    return true
end

event.reg("EV_UPDATE", NM, enter_push)

local function helptime_change(self, C, now, new_helptime)
    local old_expire = C.expire
    C.helptime = new_helptime
    C.expire = C.update + BASIC.mainline_maxtime + C.helptime
    cache.dirty(self)

    -- addition变化，会导致C.expire(new_expire)变大或变小，
    -- 在 now > old_expire时， 若变大 从old_expire到now这段时间不应该有奖励，变小时无影响

    -- 解决方法：应该设置C.expire到now，同时修正各种奖励的inner_update也到now
    local cfg = query_CFG(self, C)
    if now > old_expire then
        if C.expire > old_expire then
            C.expire = now -- 到期时间修改到现在

            local long = now - old_expire -- 各奖励内置更新时间点也修改到现在

            local common_update = utable.sub(C, "common_update")
            for nm, v in pairs(common_update) do
                common_update[nm] = v + long
            end

            if cfg.drop then
                if C.extra_update then
                    C.extra_update = C.extra_update + long
                end
            else
                C.extra_update = now
            end

            if cfg.special_drop then
                local update = C.special_update
                if old_expire < update then
                    C.special_update = math.max(now, update)
                else
                    C.special_update = update + long
                end
            else
                C.special_update = now
            end
            cache.dirty(self)
        end
    end
end

local working
event.reg("EV_ADDITION_CHANGE", NM, function(self)
    if not working then
        working = true
        skynet.fork(function()
            skynet.sleep(300)
            working = nil

            local C = cache.get(self)
            local now, changed = utime.time(), {}

            for _, k in pairs(atype) do
                local v = addition.sum(self, k)
                if C[k] ~= v then changed[k] = v end
            end

            if next(changed) then
                calc_reward(self, C, now) -- 用老的addition数据先结算一次
                for k, v in pairs(changed) do -- 写入新addition
                    C[k] = v
                    cache.dirty(self)
                end
            end

            local helptime = addition.sum(self, "helptime")
            if C.helptime ~= helptime then
                if not next(changed) then
                    calc_reward(self, C, now)
                end
                helptime_change(self, C, now, helptime)
            end
        end)
    end
end)

condition.reg(ctype.mainline, function(self, mainline)
    return self.mainline >= mainline
end)

return _M
