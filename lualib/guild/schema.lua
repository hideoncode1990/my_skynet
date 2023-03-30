local schema = require "mongo.schema"
local _M = {}

local mem_def = {
    rid = schema.ORI,
    gid = schema.ORI,
    rname = schema.ORI,
    sid = schema.ORI,
    head = schema.ORI,
    contribution = schema.ORI,
    pos = schema.ORI,
    login = schema.ORI,
    guildstar = schema.ORI,
    zdl = schema.ORI,
    punish_quit_ti = schema.ORI,
    free_quit_ti = schema.ORI,
    free_quit_cnt = schema.ORI,
    daily_cont = schema.ORI,
    last_cont_add = schema.ORI

}

function _M.gen(_schema)
    return {
        decode = function(d)
            return _schema(false, d)
        end,
        encode = function(d)
            return _schema(true, d)
        end
    }
end

_M.mem_schema = _M.gen(schema.OBJ(mem_def))

return _M
