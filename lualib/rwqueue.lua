local skynet = require "skynet"
local traceback = debug.traceback

return function()
    local in_write
    local queue = {}
    local queue_flag = {}
    local running_thread = {}
    local flag_read<const> = 1
    local flag_write<const> = 2

    local function wakeup_next()
        local head = queue_flag[1]
        if head then
            if head == flag_write then
                table.remove(queue_flag, 1)
                local thread = table.remove(queue, 1)
                running_thread[thread], in_write = true, true
                skynet.wakeup(thread)
            else
                while true do
                    local flag = queue_flag[1]
                    if flag_read == flag then
                        table.remove(queue_flag, 1)
                        local thread = table.remove(queue, 1)
                        running_thread[thread] = true
                        skynet.wakeup(thread)
                    else
                        break
                    end
                end
            end
        end
    end

    local runlock = function(thread, ok, ...)
        running_thread[thread] = nil
        if not next(running_thread) then wakeup_next() end
        assert(ok, (...))
        return ...
    end

    local rlock = function(f, ...)
        local thread = coroutine.running()
        assert(running_thread[thread] == nil, "nested locks are prohibited")
        if #queue > 0 or in_write then
            table.insert(queue, thread)
            table.insert(queue_flag, flag_read)
            skynet.wait(thread)
            assert(running_thread[thread] and not in_write) -- todo remove check
        else
            assert(not in_write) -- todo remove check
            running_thread[thread] = true
        end
        return runlock(thread, xpcall(f, traceback, ...))
    end

    local wunlock = function(thread, ok, ...)
        running_thread[thread], in_write = nil, nil
        wakeup_next()
        assert(ok, (...))
        return ...
    end

    local wlock = function(f, ...)
        local thread = coroutine.running()
        assert(running_thread[thread] == nil, "nested locks are prohibited")
        if #queue > 0 or next(running_thread) then
            table.insert(queue, thread)
            table.insert(queue_flag, flag_write)
            skynet.wait(thread)
            assert(running_thread[thread] and in_write) -- todo remove check
        else
            assert(not in_write and not next(running_thread)) -- todo remove check
            running_thread[thread], in_write = true, true
        end
        return wunlock(thread, xpcall(f, traceback, ...))
    end

    return function(iswrite, f, ...)
        if iswrite then
            return wlock(f, ...)
        else
            return rlock(f, ...)
        end
    end
end
