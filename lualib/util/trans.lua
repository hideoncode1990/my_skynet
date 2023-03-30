local _M = {}

local tp_mainline<const> = "m"
local tp_item<const> = "i"

local function generate(tp, tab)
    return "{" .. tp .. " " .. table.concat(tab, ":") .. "}"
end

function _M.mainline(id)
    return generate(tp_mainline, {id})
end

function _M.item(item)
    return generate(tp_item, item)
end

function _M.items(items)
    local ret = {}
    for _, item in ipairs(items) do table.insert(ret, _M.item(item)) end
    return table.concat(ret, " ")
end

return _M
