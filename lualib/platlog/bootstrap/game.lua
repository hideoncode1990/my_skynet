local bootstrap = require "bootstrap"
local skynet = require "skynet"

bootstrap(function()
    skynet.uniqueservice "game/platlog/heartd"
    skynet.uniqueservice "game/platlog/main"
end)
