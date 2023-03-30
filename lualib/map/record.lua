local client = require "client"
local utime = require "util.time"
local cache = require("map.cache")("record")
local objmgr = require "map.objmgr"

local _M = {}

require("map.mods") {
    name = "record",
    enter = function(self)
        objmgr.clientpush("map_record_list", {list = cache.get()})
    end
}

function _M.add(id)
    local C = cache.get()
    local record = {id = assert(id), time = utime.time_int()}
    table.insert(C, record)
    cache.dirty()
    objmgr.clientpush("map_record_add", {record = record})
end

return _M
