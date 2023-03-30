local skynet = require "skynet"
local client = require "client"
local uaward = require "util.award"
local battle_check = require "battle.checks"
require "replay"
local battled_mgr

local _M = {}

--[[
    101 不在附近
    102 怪物已死亡
    103 没有该英雄
    104 上阵类型重复
    105 英雄已死亡
    106 已有战斗
    107 没有补给值
--]]
skynet.init(function()
    battled_mgr = skynet.uniqueservice("battle/battled")
end)

local function release(ctx)
    if ctx.release then return end

    ctx.release = true
    for _, obj in pairs(ctx.plys) do
        skynet.send(obj.addr, "lua", "battle_release")
    end
    if ctx.onclose then skynet.fork(ctx.onclose) end
end

local meta = {__close = release}

local function grab_battle_ctx(ctx)
    local plys = ctx.plys
    ctx.release = true
    return setmetatable({plys = plys, onclose = ctx.onclose}, meta)
end

function _M.create(nm, bmapid, cctx, limit)
    limit = limit or 0
    cctx.plys = {}
    cctx.mapid = bmapid
    cctx.nm = nm
    cctx.limit = limit
    cctx.multi_speed = cctx.multi_speed or 1
    cctx.auto = battle_check.calc_auto(limit, cctx.auto)

    local ctx = {
        ctx = cctx,
        plys = cctx.plys,
        battled = skynet.call(battled_mgr, "lua", "alloc")
    }
    setmetatable(ctx, meta)
    return ctx
end

function _M.join(ctx, obj)
    local rid, fd, addr = obj.rid, obj.fd, obj.addr
    local plys = ctx.plys
    assert(not plys[rid])
    if not skynet.call(obj.addr, "lua", "battle_join", ctx.battled,
        ctx.ctx.limit) then return false end
    plys[rid] = {fd = fd, rid = rid, addr = addr}
    return true
end

local function ctx_push(ctx, msg, tbl)
    for _, ply in pairs(ctx.plys) do client.push(ply, msg, tbl) end
end

function _M.start(ctx, left, right, cb)
    _M.start_multi(ctx, function()
        return _M.execute(ctx, left, right)
    end, cb)
end

function _M.execute(ctx, left, right)
    ctx_push(ctx, "battle_start", ctx.ctx)
    return pcall(skynet.call, ctx.battled, "lua", "battle_start", ctx.ctx, left,
        right)
end

function _M.start_multi(ctx, loop, cb)
    skynet.fork(function()
        local gctx<close> = grab_battle_ctx(ctx)
        skynet.wakeup(ctx)
        local ok, ret = loop()
        cb(ok, ret)
    end)
    skynet.wait(ctx)
end

local function battle_endinfo(ret, award)
    return {
        win = ret.win,
        award = uaward.pack(award or {}),
        terminate = ret.terminate,
        restart = ret.restart,
        report = ret.report
    }
end

_M.battle_endinfo = battle_endinfo

function _M.push(obj, ret, award)
    client.push(obj, "battle_end", battle_endinfo(ret, award))
end

function _M.abnormal_push(obj)
    _M.push(obj, {win = 0, terminate = true})
end

function _M.multi_pack(c)
    local l = {}
    for i, list in ipairs(c) do l[i] = {team = i, list = list} end
    return l
end

function _M.multi_unpack(l)
    local c = {}
    for _, v in pairs(l) do c[v.team] = v.list end
    return c
end

return _M
