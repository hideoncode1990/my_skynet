local skynet = require "skynet"
local uniq = require "uniq.c"
local queue = require "skynet.queue"
local service = require "service"
local setting = require "setting"
local socket = require "skynet.socket"
local _MAS = require "handler.master"
local env = require "env"

local session_ctx = {}
local host, port

local function read_cmd_result(sock, ret)
    while true do
        local line = socket.readline(sock, "\n")
        table.insert(ret, line)
        if line == "<CMD OK>" or line == "<CMD Error>" then break end
    end
end

local function read_debug_result(ctx, ret)
    local sock = ctx.sock
    local buffer = ""
    while true do
        local r = socket.read(sock)
        if r then
            buffer = buffer .. r
            skynet.error("BUFFER:" .. r)
            if string.find(buffer, "<CMD OK>\n$") then
                skynet.error("DBUEG1:" .. buffer)
                ctx.indebug = nil
                break
            end
            if string.find(buffer, "<CMD Error>\n$") then
                skynet.error("DBUEG2:" .. buffer)
                ctx.indebug = nil
                break
            end
            if string.find(buffer, ":[%x][%x][%x][%x][%x][%x][%x][%x]>$") then
                skynet.error("DBUEG3:" .. buffer)
                break
            end
        else
            error("read_debug_result")
        end
    end
    table.insert(ret, buffer)
end

local function do_cmd(sctx, cmd)
    sctx.time = skynet.now()
    local sock = sctx.sock
    if socket.invalid(sock) or socket.disconnected(sock) then
        return {e = 2, m = "socket error"}
    end
    local ret = {}
    local buffer = sctx.buffer
    if buffer then
        sctx.buffer = nil
        table.insert(ret, buffer)
    end
    local session = sctx.session
    print(cmd, cmd == "")
    if not sctx.indebug and cmd == "" then
        return {e = 0, session = session, ret = buffer}
    end
    socket.write(sock, cmd .. "\n")

    if not sctx.indebug then
        if string.sub(cmd, 1, 5) == "debug" then
            skynet.error("START:" .. cmd)
            sctx.indebug = true
            read_debug_result(sctx, ret)
        else
            skynet.error("CMD:" .. cmd)
            read_cmd_result(sock, ret)
        end
    else
        skynet.error("DEBUG:" .. cmd)
        read_debug_result(sctx, ret)
    end
    return {e = 0, session = session, ret = table.concat(ret, "\n")}
end

function _MAS.run(ctx)
    local session = tonumber(ctx.body.session)
    print(session)
    local cmd = ctx.body.cmd
    local sctx = session_ctx[session]
    if not sctx then
        session = uniq.uuid()
        sctx = {
            time = skynet.now(),
            lock = queue(),
            sock = socket.open(host, port),
            indebug = nil,
            session = session
        }
        session_ctx[session] = sctx
        sctx.buffer = socket.readline(sctx.sock, "\n")
        skynet.fork(function()
            while true do
                skynet.sleep(3000)
                if skynet.now() > sctx.time + 12000 then
                    session_ctx[session] = nil
                    sctx.lock(socket.close, sctx.sock)
                    break
                end
            end
        end)
    end
    return sctx.lock(do_cmd, sctx, cmd)
end

service.start {
    master = "/console",
    init = function()
        port = setting.debugport
        host = "127.0.0.1"
        local file = assert(io.open(env.debugport, "w"))
        file:write(port)
        file:close()
        skynet.uniqueservice("debug_console", host, port)
    end
}
