local skynet = require "skynet"
local cache = require "mongo.role"("progress")
local cfgproxy = require "cfg.proxy"
local task = require "task"
local client = require "client.mods"
local CFG
local NM<const> = "progress"
local _M = {}

skynet.init(function()
    CFG = cfgproxy("task_progress")
    task.reg(NM, function(self, tp, val)
        local _type, isstring = task.type(tp)
        if isstring and not CFG[_type] then return end

        local C = cache.get(self)
        local ret = task.calc(tp, C, val, NM)
        if next(ret) then
            cache.dirty(self)
            for k, v in pairs(ret) do
                client.push(self, NM, "progress_change", {tp = k, val = v})
            end
        end
    end)
end)

require "role.mods" {
    name = NM,
    enter = function(self)
        client.enter(self, NM, "progress_info",
            {datas = task.cache(self, cache.get(self), NM)})
    end
}

function _M.check(self, tp, arg)
    return task.check(tp, arg, cache.get(self), NM)
end

return _M

