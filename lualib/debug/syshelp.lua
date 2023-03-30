local memory = require "skynet.memory"
local ext = require "ext.c"
local PID = ext.pid()

local _M = {}
function _M.jemalloc(R)
    local info = memory.jestat() -- stats.{"allocated", "resident", "retained", "mapped", "active"}
    for k, v in pairs(info) do R[string.gsub(k, "stats.", "je_")] = v end
    R.je_memory = memory.total()
    R.je_block = memory.block()
end

local cache = {}
local function filecache(name)
    local file = cache[name]
    if file then
        file:seek("set", 0)
        file:flush()
    else
        file = assert(io.open(name))
        cache[name] = file
    end
    return file
end

function _M.system_proc_statm(R)
    local file = filecache(string.format("/proc/%d/statm", PID))
    local str = file:read("*a")
    local size, resident, share, trs, lrs, drs, dt =
        str:match("(%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+)")

    R.statm_size = tonumber(size) -- vmsize/4
    R.statm_resident = tonumber(resident) -- vmrss/4
    R.statm_share = tonumber(share) -- shared pages
    R.statm_trs = tonumber(trs) -- vmexe/4	text(code)
    R.statm_drs = tonumber(drs) -- (vmdata+vmstk)/4
    R.statm_lrs = tonumber(lrs)
    R.statm_dt = tonumber(dt)
end

function _M.system_stat(R)
    local file = filecache("/proc/stat")
    local line = file:read("*l")
    local utime, ntime, stime, itime, iowtime, irqtime, sirqtime =
        line:match("cpu  (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+)")

    utime = tonumber(utime) -- user
    ntime = tonumber(ntime) -- nice
    stime = tonumber(stime) -- system
    itime = tonumber(itime) -- idle
    iowtime = tonumber(iowtime) -- iowait
    irqtime = tonumber(irqtime) -- irq
    sirqtime = tonumber(sirqtime) -- softirq

    R.stat_alltime_cpu = utime + ntime + stime + itime + iowtime + irqtime +
                             sirqtime
    local cpus = {}
    while true do
        line = file:read("*l")
        if not line then break end
        local cpuid
        cpuid, utime, ntime, stime, itime, iowtime, irqtime, sirqtime =
            line:match(
                "cpu(%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+)")
        cpuid = tonumber(cpuid)
        if not cpuid then break end
        utime = tonumber(utime) -- user
        ntime = tonumber(ntime) -- nice
        stime = tonumber(stime) -- system
        itime = tonumber(itime) -- idle
        iowtime = tonumber(iowtime) -- iowait
        irqtime = tonumber(irqtime) -- irq
        sirqtime = tonumber(sirqtime) -- softirq
        cpus[cpuid] = utime + ntime + stime + itime + iowtime + irqtime +
                          sirqtime
    end
    R.stat_cpus = cpus
end

function _M.system_proc_stat(R)
    local file = filecache(string.format("/proc/%d/stat", PID))
    local content = file:read("*a")
    local info = ext.split(content, " ")

    local utime = tonumber(info[14])
    local stime = tonumber(info[15])
    local cutime = tonumber(info[16])
    local cstime = tonumber(info[17])
    -- local starttime = tonumber(info[22])
    local vsize = tonumber(info[23])
    local rss = tonumber(info[24])

    R.stat_alltime_proc = utime + stime + cutime + cstime
    R.stat_vsize = vsize
    R.stat_rss = rss
end

local thread_idx, thread_map = 0, {}
function _M.system_thread_stat(R)
    local lfs = require "lfs"
    local ret = {}
    for name in lfs.dir(string.format("/proc/%d/task/", PID)) do
        if name ~= "." and name ~= ".." then
            local file = filecache(string.format("/proc/%d/task/%s/stat", PID,
                name))
            local content = file:read("*a")
            local info = ext.split(content, " ")

            local utime = tonumber(info[14])
            local stime = tonumber(info[15])
            local cutime = tonumber(info[16])
            local cstime = tonumber(info[17])
            local idx = thread_map[name]
            if not idx then
                idx = thread_idx + 1
                thread_map[name], thread_idx = idx, idx
            end
            ret[string.format("%02d", idx)] = utime + stime + cutime + cstime
        end
    end
    R.thrstat = ret
end

local function ignore()
end

function _M.proc_netdev_stat(R)
    local file = filecache(string.format("/proc/%d/net/dev", PID))
    file:read("*l")
    file:read("*l")
    local netdev = {}
    while true do
        local line = file:read("*l")
        if not line then break end

        local rface, content = ext.splitrow(line, ":")
        rface = rface:match("^%s*(.-)%s*$")
        local rbytes, rpackets, rerrs, rdrop, rfifo, rframe, rcompressed,
            rmulticast, tbytes, tpackets, terrs, tdrop, tfifo, tcolls, tcarrier,
            tcompressed = ext.splitrow(content, " ", "i")

        ignore(rfifo, rframe, rcompressed, rmulticast, tfifo, tcolls, tcarrier,
            tcompressed)

        netdev[rface] = {
            rbytes = tonumber(rbytes),
            rpackets = tonumber(rpackets),
            rerrs = tonumber(rerrs),
            rdrop = tonumber(rdrop),
            tbytes = tonumber(tbytes),
            tpackets = tonumber(tpackets),
            terrs = tonumber(terrs),
            tdrop = tonumber(tdrop)
        }
    end
    R.netdev = netdev
end

return _M
