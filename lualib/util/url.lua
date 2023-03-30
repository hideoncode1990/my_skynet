require("http.httpc").dns()
local urlparse = require "util.urlparse"

local _M = {}

function _M.parse(url, _path)
    local com = urlparse(url)
    local host = com.scheme .. "://" .. com.authority
    local path, query = com.path, com.query
    if _path then path = _M.path_join(path, _path) end
    return host, path, query
end

local SEP = string.byte("/")
function _M.path_join(base, url)
    local ok_b = string.byte(base, #base) == SEP
    local ok_u = string.byte(url, 1) == SEP
    if ok_b and ok_u then
        return base .. string.sub(url, 2)
    else
        if ok_b or ok_u then
            return base .. url
        else
            return base .. "/" .. url
        end
    end
end

return _M
