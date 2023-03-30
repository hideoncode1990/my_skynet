local status_type = require "battle.status_type"
local _M = {}

function _M.init(self)
    self.status_list = {}
    if self.body then
        _M.add_table(self, {status_type.no_control, status_type.no_move})
    end
end

function _M.destroy(self)
    self.status_list = {}
end

function _M.add(self, id)
    local status_list = self.status_list
    status_list[id] = (status_list[id] or 0) + 1
end

function _M.add_table(self, tb)
    for _, id in ipairs(tb) do _M.add(self, id) end
end

function _M.del(self, id)
    local status_list = self.status_list
    local cnt = status_list[id] - 1
    if cnt == 0 then
        status_list[id] = nil
    else
        status_list[id] = cnt
    end
end

function _M.delmult(self, ...)
    for _, id in ipairs({...}) do _M.del(self, id) end
end

function _M.del_table(self, tb)
    for _, id in ipairs(tb) do _M.del(self, id) end
end

function _M.check(self, id)
    return self.status_list[id]
end

function _M.check_and(self, ...)
    local status_list = self.status_list
    for _, id in ipairs({...}) do
        if not status_list[id] then return false end
    end
    return true
end

function _M.checktable_and(self, tab)
    local status_list = self.status_list
    for _, id in ipairs(tab) do if not status_list[id] then return false end end
    return true
end
function _M.check_or(self, ...)
    local status_list = self.status_list
    for _, id in ipairs({...}) do if status_list[id] then return true end end
    return false
end

function _M.checktable_or(self, tab)
    local status_list = self.status_list
    for _, id in ipairs(tab) do if status_list[id] then return true end end
    return false
end

require "battle.mods"("status", _M)
return _M
