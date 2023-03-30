local _M = {}

local REGS = {}
local function reg(name, call)
    for _, mod in pairs(REGS) do
        if mod[2] == name then error("dumplicate module " .. name) end
    end
    table.insert(REGS, {call, name})
end

function _M.init(self, bctx)
    for _, mod in ipairs(REGS) do
        local init = mod[1].init
        if init then init(self, bctx) end
    end
end

function _M.destroy(self, bctx)
    for i = #REGS, 1, -1 do
        local mod = REGS[i]
        local destroy = mod[1].destroy
        if destroy then destroy(self, bctx) end
    end
end

setmetatable(_M, {
    __call = function(_, name, call)
        reg(name, call)
    end
})

return _M
