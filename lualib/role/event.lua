local logerr = require "log.err"
local ipairs = ipairs
local xpcall = xpcall
local traceback = debug.traceback
local events = {}
local skynet = require "skynet"

local _M = {}
local list = {
    ["EV_UPDATE"] = true, -- 跨天更新
    ["EV_LVUP"] = true, -- 角色等级提升
    ["EV_VIP_LVUP"] = true, -- 角色VIP等级提升
    ["EV_NAMECHANGE"] = true, -- 角色名字修改
    ["EV_MAINLINE"] = true, -- 主线解锁
    ["EV_HERO_LVREAL_UP"] = true, -- 英雄真实等级提升
    ["EV_HERO_STAGEUP"] = true, -- 英雄升阶
    ["EV_HERO_SYNCCHG"] = true, -- 英雄同步等级变化
    ["EV_HEROBEST_CHANGE"] = true, -- 最佳英雄等级变化
    ["EV_HEAD_CHG"] = true, -- 头像修改
    ["EV_HERO_DELS"] = true, -- 删除英雄
    ["EV_HERO_LVUP"] = true, -- 英雄等级变化
    ["EV_HERO_ATTRS_CHANGE"] = true, -- 英雄属性变化
    ["EV_GUILD_QUIT"] = true, -- 离开公会
    ["EV_GUILD_JOIN"] = true, -- 加入公会
    ["EV_ADDITION_CHANGE"] = true -- 角色权益变化
}

function _M.reg(k, name, cb)
    assert(list[k] and name and cb)
    local grp = events[k]
    if not grp then
        grp = {}
        events[k] = grp
    end
    for _, node in ipairs(grp) do
        if node[2] == name then
            node[1], name = cb, nil
            logerr("duplicated call in cb %s.%s", tostring(k), tostring(node[2]))
            break
        end
    end
    if name then table.insert(grp, {cb, name}) end
end

local function occur(k, ...)
    local grp = events[k]
    if grp then
        for _, node in ipairs(grp) do
            local ok, err = xpcall(node[1], traceback, ...)
            if not ok then logerr(err) end
        end
    end
end

function _M.occur(k, ...)
    skynet.fork(occur, k, ...)
end

_M.raw_occur = occur

return _M
