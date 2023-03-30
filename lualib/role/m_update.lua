local calendar = require "calendar"
local client = require "client"
local utime = require "util.time"
local event = require "role.event"

local cb

require("role.mods") {
    name = "update",
    enter = function(self)
        if not cb then
            local function callback()
                client.push(self, "daily_update", {time = utime.time()})
                event.occur("EV_UPDATE", self)
            end
            cb = assert(calendar.subscribe(callback, "0 0 0 * * ?"))
        end
    end,
    leave = function()
        calendar.unsubscribe(cb)
        cb = nil
    end
}
