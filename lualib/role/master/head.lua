local getupvalue = require "debug.getupvalue"
local head = require "role.m_head"
local _MAS = require "handler.master"

function _MAS.head_list(self)
    local mod = require("role.mods").get(self, "head")
    local packall = getupvalue(mod.enter, "packall")
    local list = packall(self)
    list.e = 0
    return list
end

function _MAS.head_del(self, ctx)
    local id = tonumber(ctx.query.id)
    local type = ctx.query.type
    head[type .. "_del"](self, id, {flag = "MASTER"})
    return {e = 0}
end
