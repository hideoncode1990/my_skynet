local client = require "client"
local utable = require "util.table"
local passive = require "role.passive"
local cache = require "legion_trial.cache"
local cardcache, timescache = cache("card"), cache("times")
local schema = require "mongo.schema"
cardcache.schema(schema.NOBJ())
timescache.schema(schema.ORI)
local card = require("card")(cardcache, timescache)

local _M = setmetatable({}, {__index = card})

function _M.enter(self)
    local cards = card.get(self)
    client.push(self, "legion_trial_cards", {cards = cards})
end

function _M.passive_list(self)
    local passive_list = utable.copy(passive.get(self))
    return card.passive_list(passive_list, self)
end

function _M.addbag(self, id)
    card.add(id, self)
    local cards = card.get(self)
    client.push(self, "legion_trial_cards", {cards = cards})
end

function _M.clean(self)
    cardcache.clean(self)
    timescache.clean(self)
end

return _M
