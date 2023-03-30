local setting = require "setting"
local _M = {}
require("skynet").init(function()
    _M[setting.id] = true
    for _, id in ipairs(setting.merge) do _M[id] = true end
end)

return _M