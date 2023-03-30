local skynet = require "skynet"
local _M = {}

local typelist = {int = tonumber, float = tonumber, string = tostring}

local masterd
skynet.init(function()
    masterd = skynet.uniqueservice("base/masterd")
end)

local REGS = {}
local function praser(str, prefix)
    local fname, argstr = string.gmatch(str, "([%w_]+)%((.*)%)")()
    assert(fname, "parse error " .. str)
    local args = {}
    for typeid, name in string.gmatch(argstr, "([^,()]*) ([^,()]*)") do
        assert(typelist[typeid], "unsupported type " .. typeid)
        table.insert(args, {typeid, name})
    end
    REGS[fname] = {op = (prefix or "/role") .. "/" .. fname, args = args}
    return true
end

function _M.getcmd()
    return REGS
end
function _M.prepare_param(str)
    local func, args
    for _, m in ipairs {"lua@([%w_]+)%(([%w,%.;:%-%d+_]+)%)", "lua@([%w_]+)%(%)"} do
        func, args = string.gmatch(str, m)()
        if func then break end
    end
    if not func then return end
    assert(func, str)
    local store = assert(REGS[func], func .. " not exist")

    local idx = 1
    local param = {}
    for k in string.gmatch(args or "", "[%-%w%.:;_]+") do
        local set = store.args[idx]
        idx = idx + 1
        if not set then break end
        local typeid, name = set[1], set[2]
        param[name] = typelist[typeid](k)
    end
    return param, store.op
end

function _M.execute(query, op)
    return skynet.call(masterd, "lua",
                       {url = op, path = op, query = query, method = 'get'})
end

setmetatable(_M, {
    __call = function(_, str)
        assert(praser(str))
    end
})

return _M
