local socket = require 'skynet.socket'
local crypt = require "skynet.crypt"
local rc4 = require "rc4"
local ustring = require "util.string"
local skynet = require "skynet"
local sprotoloader = require "sprotoloader"
local handler = require "handler.client"

local _M = {}

local thread = {}
local retmsg = {}
local reterr = {}

local host, sender
skynet.init(function()
    local protoloader = skynet.uniqueservice "protoloader"
    local slot = skynet.call(protoloader, "lua", "index", "proto.s2c")
    host = sprotoloader.load(slot):host "package"

    slot = skynet.call(protoloader, "lua", "index", "proto.c2s")
    local sp = sprotoloader.load(slot)
    sender = host:attach(sp)
end)

local function read_message(fd)
    if socket.invalid(fd) then return end
    local s = assert(socket.read(fd, 2))
    if not s then return end
    local len = string.unpack(">H", s)
    return socket.read(fd, len), len
end

local function newcipher(secret)
    local key = table.concat {
        crypt.hmac64_md5(secret, string.char(0, 0, 0, 0, 0, 0, 0, 0)),
        crypt.hmac64_md5(secret, string.char(1, 0, 0, 0, 0, 0, 0, 0)),
        crypt.hmac64_md5(secret, string.char(2, 0, 0, 0, 0, 0, 0, 0)),
        crypt.hmac64_md5(secret, string.char(3, 0, 0, 0, 0, 0, 0, 0))
    }
    return rc4.init(key)
end

--- @param result table
local function server_response(session, result)
    local co = thread[session]
    if not co then
        skynet.error("Invalid session " .. session)
    else
        retmsg[session] = result
        thread[session] = nil
        reterr[session] = nil
        skynet.wakeup(co)
    end
end

local function ret_request(self, response, result)
    if response then
        local msg = string.pack(">s2", response(result))
        self.stream_write.append(msg)
    end
end

local function execute(f, self, args, response, name)
    local result = f(self, args)
    ret_request(self, response, result, name)
end

local function handle_msg(name, response, f, self, args)
    local ok, result = xpcall(execute, debug.traceback, f, self, args, response,
        name)
    if not ok then skynet.error(string.format("raise error = %s", result)) end
end

local function dispatch(self, msg, sz)
    local type, name, args, response = host:dispatch(msg, sz)
    if type == "REQUEST" then
        local f = handler[name]
        if f then
            handle_msg(name, response, f, self, args)
            -- else
            -- skynet.error("Invalid command " .. name)
        end
    else
        local session, result, _ = name, args, response
        skynet.fork(server_response, session, result)
    end
end

function _M.push(self, t, data)
    local msg = string.pack(">s2", sender(t, data))
    self.stream_write.append(msg)
end

--- @return table | boolean, string
function _M.request(self, ti, t, data)
    local session = skynet.genid()
    local msg = string.pack(">s2", sender(t, data, session))
    self.stream_write.append(msg)
    local co = coroutine.running()
    thread[session] = co
    skynet.timeout(ti or 1000, function()
        local o = thread[session]
        if not o then return end
        retmsg[session] = string.format("timeout %s %s", tostring(self.fd),
            tostring(t))
        reterr[session] = true
        thread[session] = nil
        skynet.wakeup(o)
    end)
    skynet.wait()
    local err, ret = reterr[session], retmsg[session]
    reterr[session], retmsg[session] = nil, nil
    if err then return error(ret) end
    local e = ret.e
    if e and e ~= 0 and not ret.m then ret.m = string.upper(t) .. e end
    return ret
end

local function create_write_stream(self, _maxbyte)
    local losebyte = 0 -- 缓存(buffer_reuse)过大已导致丢弃的数据
    local buffer = "" -- 未发送数据缓存
    local buffer_reuse = "" -- 已发送数据缓存(固定大小)
    local reusemax = _maxbyte or 65535 -- 64k缓存
    local trysend = function()
        if #buffer == 0 then return end
        local d
        socket.write(self.fd, buffer)
        d, buffer = buffer, ""

        buffer_reuse = buffer_reuse .. d
        local reuselen = #buffer_reuse
        if reuselen > reusemax then
            local lose = reuselen - reusemax -- todo 要不要直接减少固定大小数据? 减少小量数据(buffer)导致的sub行为
            losebyte = losebyte + lose
            buffer_reuse = buffer_reuse:sub(reuselen - reusemax + 1)
        end
        return true
    end
    return {
        append = function(s)
            local d = rc4.crypt(self.rc4write, s)
            buffer = buffer .. d
            skynet.fork(trysend)
        end,
        restart = function(recvbytes)
            if recvbytes < losebyte then
                return -- 服务器收到的数据 比我们丢弃的数据要少
            end
            buffer_reuse = buffer_reuse .. buffer
            buffer = ""
            if recvbytes > losebyte + #buffer_reuse then
                return -- 服务器收到的数据 比我们发送的数据还要多?
            end
            local d = string.sub(buffer_reuse, recvbytes - losebyte + 1)
            if #d > 0 then assert(socket.write(self.fd, d)) end
            return true
        end
    }
end

local function create_read_stream(self)
    local buffer = ""
    local readbyte = #buffer
    local readpacket = function()
        local bufferlen = #buffer
        if bufferlen < 2 then return end
        local len = string.unpack(">H", buffer)
        if bufferlen < 2 + len then return end
        local msg = string.unpack('>s2', buffer)
        buffer = buffer:sub(3 + len)
        return msg, len
    end
    return {
        bytes = function()
            return readbyte
        end,
        execute = function(s)
            local d = rc4.crypt(self.rc4read, s)
            readbyte = readbyte + #d
            buffer = buffer .. d
            while true do
                local msg = readpacket()
                if not msg then return end
                skynet.fork(dispatch, self, msg)
            end
        end
    }
end

local function handshake(addr, port, node)
    local fd = assert(socket.open(addr, port))
    local mykey = crypt.randomkey()
    local pubkey = crypt.dhexchange(mykey)
    local pair = crypt.base64encode(pubkey)

    local m = table.concat({0, pair, node, 0}, '\n')
    assert(socket.write(fd, string.pack(">s2", m)))

    local msg = read_message(fd)
    local tbl = ustring.split(msg, '\n')
    local id = tonumber(tbl[1])
    local otherkey = crypt.base64decode(tbl[2])
    local secret = crypt.dhsecret(otherkey, mykey)

    local rc4read, rc4write = newcipher(secret), newcipher(secret)

    local self = {
        fd = fd,
        rc4read = rc4read,
        rc4write = rc4write,
        secret = secret,
        id = id,
        index = 0,
        addr = addr,
        port = port,
        node = node
    }
    self.stream_read = create_read_stream(self)
    self.stream_write = create_write_stream(self, 65535, 1024)
    skynet.error("connect", node, "by", addr .. ":" .. port)
    return self
end

local handshake_error = {
    ['200'] = "OK",
    ['400'] = 'Malformed request', -- 数据解释失败
    ['401'] = 'Unauthorized', -- 表示 HMAC 计算错误
    ['403'] = 'Index Expired', -- 表示 Index 已经使用过
    ['404'] = 'User Not Found', -- 表示连接 id 已经无效
    ['406'] = 'Not Acceptable', -- 表示 cache 的数据流不够
    ['501'] = 'Network Error' -- 网络相关错误
}

local function handshake_reuse(self)
    socket.close(self.fd)
    local addr, port = self.addr, self.port
    local fd = assert(socket.open(addr, port))

    self.index = (self.index or 0) + 1
    local content = table.concat(
        {self.id, self.index, self.stream_read.bytes()}, '\n') .. '\n'
    local hmaccode = crypt.hmac64_md5(crypt.hashkey(content), self.secret)
    local m = content .. crypt.base64encode(hmaccode)
    assert(socket.write(fd, string.pack(">s2", m)))

    local msg = read_message(fd)
    local tbl = ustring.split(msg, '\n')
    local recvnumber = tonumber(tbl[1])
    local err = handshake_error[tbl[2]] or "unknown"
    if err ~= 'OK' then
        error("reconnect " .. addr .. ":" .. port .. " failre:" .. err)
    else
        self.fd = fd
        if not self.stream_write.restart(recvnumber) then
            error("byte resend failure") -- // 补发数据失败, 清空数据, 走重新登陆流程
        end
        skynet.error("reconnect", self.node, "by", addr .. ":" .. port,
            "stream_write restart", recvnumber)
    end
    return true
end

function _M.connect(addr, port, node)
    return handshake(addr, port, node)
end

function _M.dispatch(self)
    while not self.closed do
        local ok, msg, data = pcall(socket.read, self.fd)
        if ok then
            if msg then
                self.stream_read.execute(msg)
            else
                self.stream_read.execute(data)
                skynet.error("read socket eof")
            end
        end
        if not ok or not msg then
            if msg then skynet.error(msg) end
            if not self.closed then
                assert(handshake_reuse(self))
            else
                break
            end
        end
    end
end

function _M.close(self)
    self.closed = true
    socket.close(self.fd)
end

return _M
