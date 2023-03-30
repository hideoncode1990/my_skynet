local env = require "env"
return require("variable.default." .. env.node_type)
