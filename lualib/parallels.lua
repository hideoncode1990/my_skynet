local skynet = require "skynet"
local logerr = require "log.err"

local function request_iter(self)
    return function()
        local _resp = self._resp
        local req, resp = next(_resp)
        if req == nil then
            if self._request == 0 then return end
            if self.timeout then return end
            skynet.wait(self)
            if self.timeout then return end
            req, resp = next(_resp)
        end
        self._request = self._request - 1
        _resp[req] = nil
        return req, resp
    end
end

local request_meta = {};
request_meta.__index = request_meta

function request_meta:add(obj, ...)
    if type(obj) == "function" then
        obj = {obj, ...}
    else
        assert(type(obj) == "table")
    end
    assert(not self._resp)
    self[#self + 1] = obj
    return self
end

request_meta.__call = request_meta.add

function request_meta:close()
    if self._request > 0 then self._request = 0 end
end

request_meta.__close = request_meta.close

function request_meta:select(timeout)
    local _resp = {}
    self._resp = _resp
    if timeout then
        skynet.timeout(timeout, function()
            self.timeout = true
            if self._request > 0 then skynet.wakeup(self) end
        end)
    end
    for i, req in ipairs(self) do
        skynet.fork(function()
            _resp[i] = {xpcall(req[1], debug.traceback, table.unpack(req, 2))}
            if self._request > 0 then skynet.wakeup(self) end
        end)
    end
    self._request = #self
    return request_iter(self), nil, nil, self
end

function request_meta:wait(timeout)
    local ret = {}
    for idx, resp in self:select(timeout) do
        local ok = table.remove(resp, 1)
        if not ok then
            logerr(resp[1])
            error("parallels error")
        end
        ret[idx] = resp
    end
    return ret
end

return function(obj)
    local ret = setmetatable({}, request_meta)
    if obj then return ret(obj) end
    return ret
end
