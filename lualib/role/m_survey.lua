local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"
local client = require "client"
local cache = require("mongo.role")("survey")
local email = require "email"
local fnopen = require "role.fnopen"
local schema = require "mongo.schema"
local utime = require "util.time"
local _H = require "handler.client"

cache.schema(schema.NOBJ())

local NM<const> = "survey"

local CFG
local function push_list(self)
    if not fnopen.check_open(self, NM) then return end

    local C = cache.get(self)
    local list = {}
    for id, cfg in pairs(CFG) do
        table.insert(list, {id = id, address = cfg.address, got = C[id]})
    end
    client.push(self, "servey_list", {list = list})
end

skynet.init(function()
    CFG = cfgproxy("survey")
    fnopen.reg(NM, NM, push_list)
end)

require("role.mods") {
    name = "survey",
    load = function(self)
        local C = cache.get(self)
        local change
        for id in pairs(C) do
            if not CFG[id] then
                C[id] = nil
                change = true
            end
        end
        if change then cache.dirty(self) end
    end,
    enter = push_list
}

function _H.survey_get(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end

    local id = msg.id
    local cfg = assert(CFG[id])

    local items = cfg.items
    if not items then return {e = 0} end

    local C = cache.get(self)
    if C[id] then return {e = 0} end

    C[id] = utime.time_int()
    cache.dirty(self)

    email.send({
        target = self.rid,
        theme = cfg.theme,
        content = cfg.content,
        items = items,
        signer = cfg.signer,
        option = {flag = "survey_get", arg1 = id}
    })
    return {e = 0}
end
