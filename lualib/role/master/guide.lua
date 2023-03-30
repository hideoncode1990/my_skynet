local getupvalue = require "debug.getupvalue"
local mods = require "role.mods"
local _MAS = require "handler.master"
local client = require "client"

local function set(data, idx)
    idx = idx - 1
    local i = idx // 64 + 1
    local b = idx % 64
    for _ = #data + 1, i do table.insert(data, 0) end
    data[i] = data[i] | (1 << b)
    return data
end

function _MAS.guide(self, ctx)
    local cnt = ctx.query.cnt
    assert(cnt >= 1 and cnt <= 1000)

    local mod = mods.get(nil, "guide")
    local cache = getupvalue(mod.enter, "cache")
    local C = cache.get(self)

    for i = 1, cnt do set(C, i) end
    cache.dirty(self)

    client.push(self, "guide_info", {list = C})
    return {e = 0}
end
