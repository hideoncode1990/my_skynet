local skynet = require "skynet"
local syshelp = require "debug.syshelp"
local ext = require "ext.c"
local PAGESIZE = ext.pagesize()
local PROCESSORS = ext.cpus()

local pairs = pairs
local insert = table.insert

local cpu_proc_start

local function cpus(D, R)
    if not cpu_proc_start then cpu_proc_start = R.stat_alltime_proc end
    local cpu_proc = R.stat_alltime_proc - cpu_proc_start

    D.nodesys_cpunum_total = {"counter", PROCESSORS}
    D.nodesys_cpu_total = {"counter", cpu_proc}
    D.nodesys_cputhr_total = {"counter"}
    for id, jeffs in pairs(R.thrstat) do
        local flag = "thr=\"" .. id .. "\""
        insert(D.nodesys_cputhr_total, {jeffs, flag})
    end
end

local function mem(D, R)
    D.nodesys_skynetcmem_bytes = {"gauge", R.je_memory}
    D.nodesys_skynetcblock_bytes = {"gauge", R.je_block}
    D.nodesys_jeallocated_bytes = {"gauge", R.je_allocated}
    D.nodesys_jeactive_bytes = {"gauge", R.je_active}
    D.nodesys_jemapped_bytes = {"gauge", R.je_mapped}
    D.nodesys_jeresident_bytes = {"gauge", R.je_resident}
    D.nodesys_jeretained_bytes = {"gauge", R.je_retained}
    D.nodesys_memsize_bytes = {"gauge", R.statm_size * PAGESIZE}
    D.nodesys_memresident_bytes = {"gauge", R.statm_resident * PAGESIZE}
    D.nodesys_memshare_bytes = {"gauge", R.statm_share * PAGESIZE}
    D.nodesys_memtrs_bytes = {"gauge", R.statm_trs * PAGESIZE}
    D.nodesys_memdrs_bytes = {"gauge", R.statm_drs * PAGESIZE}
end

local function net(D, R)
    D.nodesys_net_rbytes = {"counter"}
    D.nodesys_net_rpackets = {"counter"}
    D.nodesys_net_rerrs = {"counter"}
    D.nodesys_net_rdrop = {"counter"}
    D.nodesys_net_tbytes = {"counter"}
    D.nodesys_net_tpackets = {"counter"}
    D.nodesys_net_terrs = {"counter"}
    D.nodesys_net_tdrop = {"counter"}
    for face, dev in pairs(R.netdev) do
        local flag = "face=\"" .. face .. "\""
        insert(D.nodesys_net_rbytes, {dev.rbytes, flag})
        insert(D.nodesys_net_rpackets, {dev.rpackets, flag})
        insert(D.nodesys_net_rerrs, {dev.rerrs, flag})
        insert(D.nodesys_net_rdrop, {dev.rdrop, flag})
        insert(D.nodesys_net_tbytes, {dev.tbytes, flag})
        insert(D.nodesys_net_tpackets, {dev.tpackets, flag})
        insert(D.nodesys_net_terrs, {dev.terrs, flag})
        insert(D.nodesys_net_tdrop, {dev.tdrop, flag})
    end
end

return function(D)
    local R = {}
    syshelp.jemalloc(R)
    -- syshelp.system_stat(R)
    syshelp.system_proc_statm(R)
    syshelp.system_proc_stat(R)
    syshelp.system_thread_stat(R)
    syshelp.proc_netdev_stat(R)

    D.nodesys_up = {"gauge", 1}
    D.nodesys_uptime = {"counter", skynet.now() * 10}

    cpus(D, R)
    mem(D, R)
    net(D, R)
end
