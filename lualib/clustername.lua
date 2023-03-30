local skynet = require "skynet"
local cluster = require "skynet.cluster"
local cluster_core = require "skynet.cluster.core"

local inquery_name = {}
local register_name_mt = {
    __index = function(self, name)
        if not cluster_core.isname(name) then return name end

        local waitco = inquery_name[name]
        local addr
        if waitco then
            local co = coroutine.running()
            table.insert(waitco, co)
            skynet.wait(co)
            addr = rawget(self, name)
        else
            waitco = {}
            inquery_name[name] = waitco
            addr = cluster.queryname(name)
            if addr then self[name] = addr end

            inquery_name[name] = nil
            for _, co in ipairs(waitco) do skynet.wakeup(co) end
        end
        if not addr then error("not found") end
        return addr
    end
}

return setmetatable({}, register_name_mt)
