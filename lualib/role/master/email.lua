local email = require "email"
local getupvalue = require "debug.getupvalue"
local client = require "client.mods"

local _MAS = require "handler.master"
local _H = require "handler.client"

local NM<const> = "email"
function _MAS.email_send(self, ctx)
    local body = ctx.body
    local items = body.items
    for _, item in ipairs(items) do
        if item[4] then item[4] = tonumber(item[4]) end
    end
    email.send {
        target = self.rid,
        theme = body.theme,
        content = body.content,
        items = items,
        signer = body.signer,
        option = {flag = "MASTER"}
    }
end

local function emailmod(self)
    return require("role.mods").get(self, "email")
end

function _MAS.email_list(self)
    local cache, email_foreach = getupvalue(emailmod(self).enter, "cache",
        "email_foreach")
    local LOCK = getupvalue(emailmod(self).loadafter, "LOCK")

    local C = cache.get(self)
    local list = {}
    LOCK(email_foreach, self, C, function(e)
        table.insert(list, e)
    end)
    return {e = 0, list = list}
end

function _MAS.email_del(self, ctx)
    local query = ctx.query
    local eid = tonumber(query.eid)
    local ret = _H.emaildelete(self, {id = eid}, true)
    if ret.e == 0 then client.push(self, NM, "email_del", {list = {eid}}) end
    return ret
end

function _MAS.email_delall(self)
    local ret = _H.emaildelete_all(self, nil, true)
    if ret.e == 0 then client.push(self, NM, "email_del", {list = ret.list}) end
    return ret
end
