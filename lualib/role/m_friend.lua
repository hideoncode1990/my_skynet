local skynet = require "skynet"
local client = require "client.mods"
local cfgproxy = require "cfg.proxy"
local fnopen = require "role.fnopen"
local award = require "role.award"
local awardtype = require "role.award.type"
local flowlog = require "flowlog"
local utime = require "util.time"
local event = require "role.event"
local site = require "site"
local task = require "task"
local schema = require "mongo.schema"
local cache = require("mongo.role")("friend")
local roleinfo = require "roleinfo.change"
local rolesub = require "roleinfo.subscribe"
local roleid = require "roleid"
local log = require "log"
local env = require "env"
local lock = require("skynet.queue")()

local _H = require "handler.client"
local _LUA = require "handler.lua"
local _M = {}

cache.schema(schema.OBJ {
    friendlist = schema.MAPF("rid", schema.OBJ {
        rid = schema.ORI,
        sid = schema.ORI,
        rname = schema.ORI,
        head = schema.ORI,
        level = schema.ORI,
        zdl = schema.ORI,
        leavetime = schema.ORI,
        mainline = schema.ORI,
        online = schema.ORI
    }),
    applylist = schema.MAPF("rid"),
    blacklist = schema.MAPF("rid"),
    supportlist = schema.MAPF("rid"),
    send_cnt = schema.ORI,
    accept_point = schema.ORI,
    update = schema.ORI
})

local format = string.format
local insert = table.insert
local sort = table.sort

local NM<const> = "friend"

local friend_info, FCNT, ACNT, BCNT
local SUBTAB = {}

local update_check
local BASIC, SYNCRNAME
skynet.init(function()
    SYNCRNAME = skynet.uniqueservice("game/rnamesync")
    BASIC = cfgproxy("basic")
    fnopen.reg(NM, NM, function(self)
        update_check(self)
        friend_info(self)
    end)
end)

local friend_field = {
    rname = true,
    head = true,
    level = true,
    zdl = true,
    online = true,
    leavetime = true,
    sid = true,
    rid = true,
    mainline = true
}

local black_field = {
    rname = true,
    head = true,
    level = true,
    zdl = true,
    sid = true,
    rid = true
}

local function get_support(self, rid)
    local slist = cache.getsub(self, "supportlist")
    local data = slist[rid]
    if not data then
        data = {rid = rid}
        slist[rid] = data
    end
    return data
end

local function subscribe(self, c, rid)
    local sub = rolesub.subscribe(function(data, _rid)
        local info = c[_rid]
        local change
        for k, v in pairs(data) do
            if friend_field[k] and info[k] ~= data[k] then
                info[k] = v
                change = true
            end
        end
        if change then
            cache.dirty(self)
            client.push(self, NM, "friend_info_change", info)
        end
    end, rid)
    assert(not SUBTAB[rid], self.rname .. self.rid)
    SUBTAB[rid] = sub
end

local function unsubcribe(_, rid)
    rolesub.unsubscribe(SUBTAB[rid])
    SUBTAB[rid] = nil
end

local function check_support(self, C, now)
    if not utime.same_day(now, (C.update or 0)) then
        C.update = now
        C.send_cnt = 0
        C.accept_point = 0
        C.supportlist = {}
        cache.dirty(self)
    end
end

local function check_applylist(self, C, now)
    local long = BASIC.friend_apply_save
    local applylist = C.applylist or {}
    local change
    for rid, v in pairs(applylist) do
        if now >= v.time + long then
            unsubcribe(self, rid)
            applylist[rid] = nil
            change = true
        end
    end
    if change then cache.dirty(self) end
end

update_check = function(self)
    local C = cache.get(self)
    local now = utime.time(self)
    check_support(self, C, now)
    check_applylist(self, C, now)
end

local function selfinfo(self)
    local info = {}
    for k in pairs(friend_field) do info[k] = self[k] end
    -- self 上没有leavetime
    info.leavetime = roleinfo.query_cache(self, "leavetime")
    return info
end

local function un_sub()
    for k, v in pairs(SUBTAB) do
        rolesub.unsubscribe(v)
        SUBTAB[k] = nil
    end
end

friend_info = function(self)
    local C = cache.get(self)
    for rid, info in pairs(C.friendlist or {}) do
        local s = get_support(self, rid)
        info.send = s.send
        info.accept = s.accept
    end
    client.enter(self, NM, "friend_info", C)
end

local function cnt_and_sub_init(self)
    local cnttab = {FCNT, ACNT, BCNT}
    for k, tp in ipairs({"friendlist", "applylist", "blacklist"}) do
        local cnt = 0
        local data = cache.getsub(self, tp)
        for rid in pairs(data) do
            cnt = cnt + 1
            if k ~= 3 then subscribe(self, data, rid) end
        end
        cnttab[k] = cnt
    end
    FCNT, ACNT, BCNT = table.unpack(cnttab)
    self.friendcnt = FCNT
end

require("role.mods") {
    name = NM,
    loaded = function(self)
        cnt_and_sub_init(self)
        update_check(self)
    end,
    enter = function(self)
        friend_info(self)
    end,
    unload = un_sub
}

local function AGENTCALL(sid, rid, func, ...)
    local addr = {node = format("%s_%d", env.node_type, sid), addr = "@manager"}
    local ok, e, err = pcall(site.call, addr, "agent_call", rid, "lua", func,
        ...)
    if not ok then return false, 101 end
    return e, err
end

local function AGENTSEND(sid, rid, func, ...)
    local addr = {node = format("%s_%d", env.node_type, sid), addr = "@manager"}
    site.send(addr, "agent_send", rid, "lua", func, ...)
end

local function friend_del(self, flist, rid)
    assert(flist[rid])
    flist[rid] = nil
    cache.dirty(self)

    unsubcribe(self, rid)
    FCNT = FCNT - 1
    self.friendcnt = FCNT
    client.push(self, NM, "friend_del", {rids = {rid}})
end

local function friend_add(self, flist, rid, info)
    assert(not flist[rid])
    flist[rid] = info
    cache.dirty(self)

    subscribe(self, flist, rid)
    FCNT = FCNT + 1
    self.friendcnt = FCNT
    local s = get_support(self, rid)
    info.send = s.send
    info.accept = s.accept
    client.push(self, NM, "friend_add", {list = {[rid] = info}})
    flowlog.role_act(self, {flag = "friend_add", arg1 = rid})
end

local function apply_add(self, alist, rid, applicant)
    assert(not alist[rid])
    alist[rid] = applicant
    cache.dirty(self)
    ACNT = ACNT + 1
    subscribe(self, alist, rid)
    if fnopen.check_open(self, NM) then
        client.push(self, NM, "friend_applylist", {list = alist})
    end
end

local function apply_del(self, alist, rid)
    assert(alist[rid])
    unsubcribe(self, rid)
    alist[rid] = nil
    cache.dirty(self)
    ACNT = ACNT - 1
    if fnopen.check_open(self, NM) then
        client.push(self, NM, "friend_applylist", {list = alist})
    end
end

-- 数据不同步，即一方是好友，另一方不是好友时，数据恢复成互相不是好友的状态
function _LUA.friend_apply(self, applicant)
    local rid = applicant.rid
    local blist = cache.getsub(self, "blacklist")
    if blist[rid] then return false, 5 end

    local flist = cache.getsub(self, "friendlist")
    if flist[rid] then
        log("friend_apply_del_friend %s %s", self.rid, rid)
        friend_del(self, flist, rid)
    end -- 数据同步处理

    if ACNT >= BASIC.friend_apply_limit then return false, 6 end
    if FCNT >= BASIC.friend_limit then return false, 9 end

    local alist = cache.getsub(self, "applylist")
    if alist[rid] then return false, 7 end

    applicant.time = utime.time_int()
    apply_add(self, alist, rid, applicant)
    return true
end

function _LUA.friend_apply_res(self, from)
    local rid = from.rid
    local blist = cache.getsub(self, "blacklist")
    if blist[rid] then return false, 4 end

    local flist = cache.getsub(self, "friendlist")
    if flist[rid] then
        log("friend_apply_res_del_friend %s %s", self.rid, rid)
        friend_del(self, flist, rid)
    end -- 数据同步处理

    if FCNT >= BASIC.friend_limit then return false, 5 end

    local alist = cache.getsub(self, "applylist")
    if alist[rid] then apply_del(self, alist, rid) end
    friend_add(self, flist, rid, from)

    return true, selfinfo(self)
end

function _LUA.friend_delete(self, rid)
    local flist = cache.getsub(self, "friendlist")
    if not flist[rid] then return end
    friend_del(self, flist, rid)
end

function _LUA.friend_support_arrive(self, rid, time)
    local flist = cache.getsub(self, "friendlist")
    if not flist[rid] then return false, 6 end -- 数据不同步（不是好友关系）
    local now = utime.time_int()
    if not utime.same_day(now, time) then return false, 7 end

    local s = get_support(self, rid)
    if s.accept then return true, 8 end -- 数据不同步（同一天某时刻收到过，发送方未记录）

    s.accept = 1
    s.time = now
    cache.dirty(self)
    client.push(self, NM, "friend_support_arrive", s)
    return true
end

function _M.check_black(self, rid)
    return cache.getsub(self, "blacklist")[rid]
end

function _M.flist_get(self)
    return cache.getsub(self, "friendlist")
end

_LUA.friend_check_black = _M.check_black

function _H.friend_query(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local rname = assert(msg.rname)
    local ok, ret = skynet.call(SYNCRNAME, "lua", "rname_query", rname)

    if not ok then return {e = ret} end

    local flist = cache.getsub(self, "friendlist")
    local blist = cache.getsub(self, "blacklist")
    ret[self.rid] = nil

    local list = {}
    for rid, info in pairs(ret) do
        if not flist[rid] and not blist[rid] then
            table.insert(list, info)
        end
    end
    flowlog.role_act(self, {flag = "friend_query", arg1 = rname})
    return {e = 0, list = list}
end

--[[
    1 功能未开放 2在黑名单中 3已是好友 4自己好友已满 5在对方的黑名单里
    6 对方申请已满 7已有该申请 8无法向自己申请 9 对方好友已满
    101对方服务器关闭
--]]
function _H.friend_apply(self, msg)
    return lock(function()
        if not fnopen.check_open(self, NM) then return {e = 1} end
        local rid = assert(msg.rid)

        if rid == self.rid then return {e = 8} end
        local blist = cache.getsub(self, "blacklist")
        if blist[rid] then return {e = 2} end

        local flist = cache.getsub(self, "friendlist")
        if flist[rid] then return {e = 3} end

        if FCNT >= BASIC.friend_limit then return {e = 4} end

        local sid = roleid.getsid(rid)
        local ok, e = AGENTCALL(sid, rid, "friend_apply", selfinfo(self))
        if not ok then return {e = e} end

        flowlog.role_act(self, {flag = "friend_apply", arg1 = rid, arg2 = sid})
        return {e = 0}
    end)
end

local function apply_res(self, rid, agree)
    local alist = cache.getsub(self, "applylist")
    if not alist[rid] then return {e = 2} end

    if agree == 1 then
        if FCNT >= BASIC.friend_limit then return {e = 3} end

        local flist = cache.getsub(self, "friendlist")
        if flist[rid] then return {e = 7} end

        local sid = roleid.getsid(rid)
        local ok, e = AGENTCALL(sid, rid, "friend_apply_res", selfinfo(self))
        if ok then
            if flist[rid] then return {e = 7} end
            apply_del(self, alist, rid)
            friend_add(self, flist, rid, e)
        else
            return {e = e}
        end
    else
        apply_del(self, alist, rid)
    end
    flowlog.role_act(self, {flag = "friend_apply_res", arg1 = rid, arg2 = agree})
    return {e = 0}
end

local function apply_resonekey(self, agree)
    local alist = cache.getsub(self, "applylist")
    if not next(alist) then return {e = 6} end
    if agree == 1 then
        local flist = cache.getsub(self, "friendlist")
        if FCNT >= BASIC.friend_limit then return {e = 3} end

        local temp = {}
        for rid in pairs(alist) do temp[rid] = roleid.getsid(rid) end
        -- call出去后，alist可能变，temp不会变
        for rid, sid in pairs(temp) do
            local ok, info = AGENTCALL(sid, rid, "friend_apply_res",
                selfinfo(self))
            if ok and not flist[rid] then
                if alist[rid] then apply_del(self, alist, rid) end
                friend_add(self, flist, rid, info)
                if FCNT >= BASIC.friend_limit then break end
            end
        end
        cache.dirty(self)
    else
        if next(alist) then
            for rid in pairs(alist) do
                unsubcribe(self, rid)
                alist[rid] = nil
                ACNT = ACNT - 1
            end
            cache.dirty(self)
            client.push(self, NM, "friend_applylist", {list = alist})
        else
            return {e = 8}
        end
    end
    return {e = 0}
end

--[[
    1 功能未开放 2没有该申请 3自己好友达到上限 4自己在对方的黑名单中
    5 对方好友已达上限 6批量同意没有可以加的 7已是好友
    8批量忽略没有可以忽略的 9 添加好友失败 101服务器关闭
--]]
function _H.friend_apply_res(self, msg)
    return lock(function()
        if not fnopen.check_open(self, NM) then return {e = 1} end
        local rid, agree = msg.rid, msg.agree
        if rid then
            return apply_res(self, rid, agree)
        else
            return apply_resonekey(self, agree)
        end
    end)
end

function _H.friend_delete(self, msg)
    return lock(function()
        if not fnopen.check_open(self, NM) then return {e = 1} end
        local rids = msg.rids
        assert(next(rids))
        local flist = cache.getsub(self, "friendlist")
        for _, rid in ipairs(rids) do
            if not flist[rid] then return {e = 2} end
        end

        for _, rid in ipairs(rids) do
            unsubcribe(self, rid)
            local info = flist[rid]
            flist[rid] = nil
            FCNT = FCNT - 1
            self.friendcnt = FCNT
            AGENTSEND(info.sid, rid, "friend_delete", self.rid)
        end
        cache.dirty(self)
        client.push(self, NM, "friend_del", {rids = rids})

        flowlog.role_act(self, {flag = "friend_delete", arg1 = rids})
        return {e = 0}
    end)
end

--[[
    1 功能未开放 2不能操作自己 3已在黑名单中
--]]

local function black_filter(s_info, c_info)
    local ret = {}
    for k in pairs(black_field) do ret[k] = s_info[k] or c_info[k] or 0 end
    return ret
end

function _H.friend_blacklist_in(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end

    local rid = msg.rid
    if rid == self.rid then return {e = 2} end
    local blist = cache.getsub(self, "blacklist")
    if blist[rid] then return {e = 3} end
    if BCNT >= BASIC.friend_black_limit then return {e = 4} end

    local info = roleinfo.query(rid) or {} -- 服务器查询roleinfo
    blist[rid] = black_filter(info, msg) -- 先用服务器信息，备用客户端信息

    cache.dirty(self)
    BCNT = BCNT + 1

    local flist = cache.getsub(self, "friendlist")
    local sid = roleid.getsid(rid)
    if flist[rid] then
        friend_del(self, flist, rid)
        AGENTSEND(sid, rid, "friend_delete", self.rid)
    end

    local alist = cache.getsub(self, "applylist")
    if alist[rid] then apply_del(self, alist, rid) end

    flowlog.role_act(self, {flag = "friend_blacklist_in", arg1 = rid})
    return {e = 0}
end

function _H.friend_blacklist_out(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local rid = msg.rid
    local blist = cache.getsub(self, "blacklist")
    if rid then
        if rid == self.rid then return {e = 2} end
        if not blist[rid] then return {e = 3} end
        blist[rid] = nil
        cache.dirty(self)
        BCNT = BCNT - 1
    else
        if not next(blist) then return {e = 4} end
        local C = cache.get(self)
        C.blacklist = {}
        cache.dirty(self)
        BCNT = 0
    end
    flowlog.role_act(self, {flag = "friend_blacklist_out", arg1 = rid})
    return {e = 0}
end

--[[
    1 功能未开放 2赠送次数超限 3不是好友关系 4本地已赠送
    6 数据不同步，不是好友关系 7已跨天 8数据不同步，对方已接收过 9本地已赠送
    101 对方服务器无响应
--]]
function _H.friend_support_send(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end

    local C = cache.get(self)
    local send_cnt = C.send_cnt or 0
    if send_cnt >= BASIC.friend_give_limit then return {e = 2} end

    local rid = msg.rid
    local flist = cache.getsub(self, "friendlist")
    if not flist[rid] then return {e = 3} end

    local sinfo = get_support(self, rid)
    if sinfo.send then return {e = 4} end

    local sid = roleid.getsid(rid)
    local ok, e = AGENTCALL(sid, rid, "friend_support_arrive", self.rid,
        utime.time_int())
    if e == 6 then friend_del(self, flist, rid) end -- 数据不同步的处理
    if not ok then return {e = e} end
    if sinfo.send == 1 then return {e = 9, send_cnt = send_cnt} end

    sinfo.send = 1
    C.send_cnt = send_cnt + 1
    task.trigger(self, "friend_support")
    task.trigger(self, "friend_support_point", BASIC.friend_supply_point)
    cache.dirty(self)

    if e == 8 then
        return {e = 8, send_cnt = C.send_cnt}
    else
        flowlog.role_act(self,
            {flag = "friend_support_send", arg1 = rid, arg2 = sid})
        return {e = 0, send_cnt = C.send_cnt}
    end
end
-- accept: nil 没有收到 1收到没领  2已领
--[[
     1功能未开放  2不是好友关系 3没有收的到支援点，4已经领取支援点 5超出领取上限
--]]
function _H.friend_support_accept(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local rid = msg.rid
    local flist = cache.getsub(self, "friendlist")
    if not flist[rid] then return {e = 2} end

    local sinfo = get_support(self, rid)
    if not sinfo.accept then return {e = 3} end
    if sinfo.accept == 2 then return {e = 4} end

    local C = cache.get(self)
    local accept_point = C.accept_point or 0
    if accept_point >= BASIC.friend_supply_getlimit then return {e = 5} end

    sinfo.accept = 2
    C.accept_point = accept_point + BASIC.friend_supply_point
    cache.dirty(self)

    assert(award.add(self, {flag = "friend_support_accept", arg1 = rid},
        {{awardtype.support, 0, BASIC.friend_supply_point}}))
    return {e = 0, accept_point = accept_point}
end

function _H.friend_support_onekey(self)
    if not fnopen.check_open(self, NM) then return {e = 1} end

    local getlimit, givelimit, point = BASIC.friend_supply_getlimit,
        BASIC.friend_give_limit, BASIC.friend_supply_point

    local flist = cache.getsub(self, "friendlist")
    local success = roleinfo.query_list(flist,
        {"online", "logintime", "leavetime"})

    local C = cache.get(self)
    local send_cnt = C.send_cnt or 0
    local accept_point = C.accept_point or 0

    if send_cnt >= givelimit and accept_point > getlimit then return {e = 2} end

    local onlist, offlist, accept = {}, {}, {}

    for rid, info in pairs(flist) do
        local rinfo = success[rid]
        local sinfo = get_support(self, rid)
        if rinfo and not sinfo.send then
            if rinfo.online then
                insert(onlist,
                    {rid = info.rid, sid = info.sid, time = rinfo.logintime})
            else
                insert(offlist, {
                    rid = info.rid,
                    sid = info.sid,
                    time = rinfo.leavetime or 0
                })
            end
        end
        if sinfo.accept == 1 then insert(accept, sinfo) end
    end

    if not next(onlist) and not next(offlist) and not next(accept) then
        return {e = 3}
    end

    local function sort_func(a, b)
        return a.time < b.time
    end
    sort(onlist, sort_func)
    sort(offlist, function(a, b)
        return a.time > b.time
    end)
    for _, v in ipairs(offlist) do insert(onlist, v) end

    sort(accept, sort_func)

    local change = {}
    local option = {flag = "friend_support_onekey"}
    if accept_point < getlimit then
        local total = 0
        for _, v in ipairs(accept) do
            local rid = v.rid
            local sinfo = get_support(self, rid)
            sinfo.accept = 2
            accept_point = accept_point + point
            total = total + point

            change[rid] = sinfo
            if accept_point >= getlimit then break end
        end
        if total > 0 then
            assert(award.add(self, option, {{awardtype.support, 0, total}}))
        end
    end

    local sum_cnt, sum_point = 0, 0
    if send_cnt < givelimit then
        local now = utime.time_int()
        for _, v in ipairs(onlist) do
            local rid = v.rid
            local ok = AGENTCALL(v.sid, rid, "friend_support_arrive", self.rid,
                now)
            if ok then
                local sinfo = get_support(self, rid)
                if not sinfo.send then
                    sinfo.send = 1
                    send_cnt = send_cnt + 1
                    change[rid] = sinfo
                    sum_cnt = sum_cnt + 1
                    sum_point = sum_point + point
                end
                if send_cnt >= givelimit then break end
            end
        end
    end

    if next(change) then
        C.accept_point = accept_point
        C.send_cnt = send_cnt
        cache.dirty(self)
        client.push(self, NM, "friend_support_onekey", {
            accept_point = accept_point,
            send_cnt = send_cnt,
            change = change
        })
        task.trigger(self, "friend_support", sum_cnt)
        task.trigger(self, "friend_support_point", sum_point)
    else
        return {e = 4}
    end
    flowlog.role_act(self, option)
    return {e = 0}
end

event.reg("EV_UPDATE", NM, function(self)
    update_check(self) -- 功能没开放 也能收到好友申请列表，需要检测列表是否过期
    if fnopen.check_open(self, NM) then friend_info(self) end
end)

return _M
