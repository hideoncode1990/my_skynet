local env = require "env"

local default
do
    local config = {game = 'DB_GAME', func = "DB_FUNC"}
    default = assert(config[env.node_type])
end
return default
