local skynet = require "skynet"
local reference_client = require "reference.client"
local rolehelp = require "mongo.rolehelp"
local log = require "log"

local roles = {}

local role_agent = 0
local prepool = {}
local presize = 1
local in_prepare

local _LUA = require "handler.lua"
local _M = {}
local QUIT = nil

local dbmgr
skynet.init(function()
    dbmgr = skynet.uniqueservice("db/mgr")
end)

local function thread_prepareagent(sz)
    for _ = #prepool + 1, sz or presize do
        table.insert(prepool, skynet.newservice("game/agent"))
    end
end

local function new_agent(role)
    local agent = table.remove(prepool)
    if not agent then agent = skynet.newservice("game/agent") end
    role_agent = role_agent + 1
    if not in_prepare then
        in_prepare = true
        skynet.fork(function()
            local ok, err = pcall(thread_prepareagent)
            in_prepare = nil
            if not ok then error(err) end
        end)
    end
    local ok, err = pcall(skynet.call, agent, "lua", "load", role)
    if not ok then
        skynet.send(agent, "lua", "stop")
        error(err)
    end
    return agent
end

local assign_in, assign_all, assign_time = 0, 0, 0
local assigning = {}
local function agent_load(role)
    assert(not QUIT)
    local rid = role.rid
    local agent = roles[rid]
    if agent then return agent end
    local waitlist = assigning[rid]
    if waitlist then
        table.insert(waitlist, (coroutine.running()))
        skynet.wait()
        agent = roles[rid]
        if not agent then error("agent load failure " .. rid) end
        return agent
    else
        waitlist = {}
        assigning[rid] = waitlist
        assign_in = assign_in + 1
        local ti = skynet.hpc()
        local ok
        ok, agent = pcall(new_agent, role)
        assign_in, assign_all = assign_in - 1, assign_all + 1
        assign_time = assign_time + (skynet.hpc() - ti) // 1000000
        assigning[rid] = nil

        for _, co in ipairs(waitlist) do skynet.wakeup(co) end

        if not ok then
            error(agent)
        else
            roles[rid] = agent
        end
        return agent
    end
end

local function query_agent(rid, role)
    rid = assert(tonumber(rid))
    while true do
        local agent = roles[rid]
        if agent then
            local ref = reference_client.ref(agent, true)
            if ref then return ref end
            skynet.yield()
        else
            if role == nil then
                local proxy = skynet.call(dbmgr, "lua", "query", "DB_GAME")
                role = rolehelp.find(proxy, rid)
                if not role then error("role not exist " .. rid) end
            end
            agent_load(role)
        end
    end
end

local function query_agent_loaded(rid)
    local agent = roles[rid]
    if agent then
        local ref = reference_client.ref(agent, true)
        if ref then return ref end
    end
end

_M.query_agent = query_agent
_M.query_agent_loaded = query_agent_loaded

function _M.anyrole(maxcnt)
    local rlist = {}
    local count = 1
    for rid in pairs(roles) do
        if count < maxcnt then rlist[rid] = true end
        count = count + 1
    end
    return rlist
end

function _LUA.prepareagent()
    thread_prepareagent(1)
    skynet.fork(thread_prepareagent)
end

function _LUA.agent_call_loaded(rid, ...)
    local ref<close> = query_agent_loaded(rid)
    if ref then return skynet.call(ref.addr, ...) end
end

function _LUA.agent_call(rid, ...)
    local ref<close> = query_agent(rid)
    return skynet.call(ref.addr, ...)
end

function _LUA.agent_send(rid, ...)
    local ref<close> = query_agent(rid)
    return skynet.send(ref.addr, ...)
end

function _LUA.agent_send_loaded(rid, ...)
    local ref<close> = query_agent_loaded(rid)
    if ref then skynet.send(ref.addr, ...) end
end

function _LUA.agent_online_send(rid, ...)
    _LUA.agent_send_loaded(rid, "lua", "online_send", ...)
end

function _LUA.agent_send_online_all(...)
    local copy = {}
    for rid in pairs(roles) do copy[rid] = true end
    for rid in pairs(copy) do _LUA.agent_online_send(rid, ...) end
end

function _LUA.dispatch_agent_send(cmd, rid, ...)
    local agent = roles[rid]
    if agent then skynet.call(agent, "lua", cmd, ...) end
end

function _LUA.dispatch_call_agent(cmd, rid, ...)
    local agent = roles[rid]
    if agent then
        return true, skynet.call(agent, "lua", cmd, ...)
    else
        return false
    end
end

function _LUA.agent_exit(fd, rid, addr)
    if rid then
        if roles[rid] then
            roles[rid] = nil
            role_agent = role_agent - 1
        end
    end
    if fd then _LUA.detachagent(fd, "agent_exit") end
    if addr then
        for idx, agent in ipairs(prepool) do
            if agent == addr then
                table.remove(prepool, idx)
                break
            end
        end
    end
end

local function stop_thread(us)
    while true do
        local rid, agent = next(us)
        if not rid then break end
        us[rid] = nil
        if roles[rid] then
            local ok, err = pcall(skynet.call, agent, "lua", "stop")
            if not ok then log(err) end
        end
    end
end

function _LUA.stopagent(quit)
    if quit then QUIT = true end
    while assign_in > 0 do skynet.sleep(10) end
    while next(roles) do
        local copy = {}
        for rid, agent in pairs(roles) do copy[rid] = agent end
        for _ = 1, 100 do skynet.fork(stop_thread, copy) end
        while next(copy) do skynet.sleep(50) end
        skynet.sleep(50)
    end
    for _, agent in pairs(prepool) do skynet.call(agent, "lua", "stop") end
end

_M.stopagent = _LUA.stopagent

require("monitor.registry")("useragent", function(D)
    D.node_agentassign = {"gauge", assign_in}
    D.node_agentassign_total = {"counter", assign_all}
    D.node_agentassign_time_total = {"counter", assign_time}
    D.node_roleagents = {"gauge", role_agent}
end)

return _M
