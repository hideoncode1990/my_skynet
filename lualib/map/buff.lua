local objmgr = require "map.objmgr"
local buffcache = require("map.cache")("buff")
local paracache = require("map.cache")("para")
local card = (require "card")(buffcache, paracache)

local insert = table.insert

local _M = {}

require("map.mods") {
    name = "buff",
    enter = function()
        local list = {}
        for id, cnt in pairs(card.get()) do
            insert(list, {id = id, cnt = cnt})
        end
        objmgr.clientpush("map_buff_list", {list = list})
    end
}

function _M.add(id)
    objmgr.clientpush("map_buff_add", {list = {{id = id, cnt = card.add(id)}}})
end

function _M.get()
    return card.get()
end

function _M.passive_list()
    return card.passive_list(objmgr.agent_call("passive_get"))
end

function _M.passive_table(k)
    return card.passive_table(k)
end

function _M.trigger(k, v)
    card.trigger(k, v)
end

return _M
