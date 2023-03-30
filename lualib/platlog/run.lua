local skynet = require "skynet"
local utime = require "util.time"
local default = require "platlog.default"
local logerr = require "log.err"
local sep = utf8.char(0x01)

return function(name)
    local circqueue = require "circqueue"
    local logfmt = require(string.format("platlog.fmt.%s", name))

    local xpcall = xpcall
    local traceback = debug.traceback

    local cntall = 0

    local _M = {}

    local function encode(data)
        local ret = {}
        for i, k in ipairs(logfmt) do
            local v = data[k] or default[k]
            ret[i] = v
            if not v then
                error(string.format("platlog_%s not found %s", name, k))
            end
        end
        local s = table.concat(ret, sep)
        return s
    end

    local file, file_fmt
    local empty = true
    local function get_file(fmt)
        if fmt ~= file_fmt then
            if file then
                file:close()
                file = nil
            end
            local path = string.format(fmt, name)
            file = assert(io.open(path, "a+b"))
            empty = true
            local source = file:read()
            if source then
                empty = false
                if source == "null" then
                    file:close()
                    file = nil
                    file = assert(io.open(path, "w+b"))
                    empty = true
                end
            end
            file_fmt = fmt
        end
        return file
    end

    local dirty
    local function wait_flush()
        skynet.sleep(300)
        dirty = nil
        if file then file:flush() end
    end

    local function write(fmt, data)
        local f = get_file(fmt)
        empty = false
        f:write(data, '\n')
        if not dirty then
            dirty = true
            skynet.fork(wait_flush)
        end
    end

    local working
    local queue = circqueue()
    local function runloop()
        while true do
            local fmt = queue.pop()
            if fmt then
                write(fmt, queue.pop())
            else
                break
            end
        end
    end

    local function run()
        skynet.sleep(20)
        local ok, err = xpcall(runloop, traceback)
        if not ok then logerr(err) end
        working = nil
    end

    local function checkwork()
        if not working then
            working = true
            skynet.fork(run)
        end
    end

    function _M.add(fmt, ...)
        local s = encode(...)
        queue.push(fmt)
        queue.push(s)
        checkwork()
        cntall = cntall + 1
    end

    function _M.flush(fmt)
        local f = get_file(fmt)
        if f then f:flush() end
    end

    function _M.statistic()
        return cntall, queue.size() // 2
    end

    function _M.flush_empty_file(fmt, force)
        if force or fmt ~= file_fmt then
            if empty then file:write("null", "\n") end
            get_file(fmt)
        end
    end

    function _M.check_write_over()
        if queue.size() > 0 then
            checkwork()
            return false
        else
            return true
        end
    end

    return _M
end
