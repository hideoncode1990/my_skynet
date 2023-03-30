local skynet = require "skynet"
local memory = require "skynet.memory"
local skynetdebug = require "skynet.debug"

local function getupvalue(func, name)
    for i = 1, math.maxinteger do
        local nm, value = debug.getupvalue(func, i)
        if not nm then break end
        if nm == name then return value, i, name end
    end
    assert("not found upvalue " .. name)
end

local session_id_coroutine = getupvalue(skynet.task, "session_id_coroutine")
local function task()
    local ret = {}
    local traceback = _G.debug.debug_traceback or debug.traceback
    for _, co in pairs(session_id_coroutine) do
        local bt = traceback(co)
        local cos = ret[bt]
        if cos then
            table.insert(cos, tostring(co))
        else
            ret[bt] = {tostring(co)}
        end
    end
    local tks = {}
    for bt, cos in pairs(ret) do table.insert(tks, {bt = bt, cos = cos}) end
    return tks
end

local function taskdetail(co)
    for _, _co in pairs(session_id_coroutine) do
        if co == tostring(_co) then return debug.traceback(_co) end
    end
    return "not exist session"
end

skynetdebug.reg_debugcmd("DETAIL_TASK", function(session)
    skynet.retpack(taskdetail(session))
end)

skynetdebug.reg_debugcmd("DETAIL", function(tsk)
    local info = memory.info()
    local kb = collectgarbage "count"
    local address = skynet.self()
    local ret = {
        addr = string.format("%08x", address),
        name = _G.SERVICE_NAME,
        mem = string.format("%.2f Kb", kb),
        mqlen = skynet.stat "mqlen",
        cpu = skynet.stat "cpu",
        message = skynet.stat "message",
        task = {},
        cmem = info[address] or 0,
        cmem_total = memory.total(),
        cmem_block = memory.block()
    }
    if tsk == 1 then ret.task = task() end
    skynet.retpack(ret)
end)
