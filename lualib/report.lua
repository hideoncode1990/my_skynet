return function(dbname, collection)
    local _M = {}
    local mongo = require("mongo.help.pool")(dbname, collection)

    function _M.query(list)
        local ret = {}
        for k, q in pairs(list) do
            local d = mongo("findone", collection, q)
            if d then
                d._id = nil
                ret[k] = d
            end
        end
        return ret
    end

    function _M.query_one(q)
        return mongo("findone", collection, q)
    end

    function _M.query_defalut(q, limit, ...)
        return mongo("findall", collection, q, {}, nil, limit, ...)
    end

    function _M.add(data)
        return mongo("safe", "insert", collection, data)
    end

    function _M.del(selector)
        return mongo("delete", collection, selector)
    end

    return _M

end
