local skynet = require "skynet"
require "handler.mcast"

local mcastd
local dispatch = {}

local chan = {}
local chan_meta = {
    __index = chan,
    __gc = function(self)
        self:unsubscribe()
    end,
    __tostring = function(self)
        return string.format("[mcast:%s]", self.channel)
    end
}

function chan:delete()
    local c = assert(self.channel)
    skynet.send(mcastd, "lua", "DEL", c)
    self.channel = nil
end

function chan:publish(...)
    local c = assert(self.channel)
    skynet.call(mcastd, "lua", "PUB", c, ...)
end

function chan:subscribe(wait)
    local c = assert(self.channel)
    dispatch[c] = self
    skynet.call(mcastd, "lua", "SUB", c, wait)
end

function chan:link(node)
    local c = assert(self.channel)
    skynet.call(mcastd, "lua", "LINK", c, node)
end

function chan:unsubscribe()
    local c = assert(self.channel)
    if dispatch[c] then
        dispatch[c] = nil
        skynet.send(mcastd, "lua", "USUB", c)
    end
end

local function dispatch_subscribe(_, _, channel, ...)
    skynet.ignoreret()
    local self = dispatch[channel]
    if not self then error("Unknown channel " .. channel) end
    self.__dispatch(...)
end

skynet.init(function()
    mcastd = skynet.uniqueservice "mcastd"
    skynet.dispatch("mcast", dispatch_subscribe)
end)

return function(channel, dispatcher)
    local self = {channel = channel, __dispatch = dispatcher}
    return setmetatable(self, chan_meta)
end
