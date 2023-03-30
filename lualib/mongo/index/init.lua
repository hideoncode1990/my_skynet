local env = require "env"
return require("mongo.index." .. env.node_type)
