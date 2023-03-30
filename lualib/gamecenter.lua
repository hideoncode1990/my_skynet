local json = require "rapidjson.c"
local skynet = require "skynet"
local httpc = require "http.httpc"
local uurl = require "util.url"
local setting = require "setting"
local log = require "log"

local header = {
    ["Content-Type"] = "application/json;charset=UTF-8",
    ["nodegroup"] = nil
}

skynet.init(function()
    header["nodegroup"] = setting.group
end)

local cache = setmetatable({}, {
    __mode = "v",
    __index = function(t, k)
        local v = {uurl.parse(setting.gamecenter, k)}
        -- local v = {uurl.parse("http://192.168.6.30:4000", k)}
        t[k] = v
        return v
    end
})

local function escape(s)
    return (string.gsub(s, "([^A-Za-z0-9_])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local _M = {}
function _M.post(url, query, data)
    local recv_header = {}
    local body = json.encode(data)
    local host, path = table.unpack(cache[url])

    local urlfull = path
    if query then
        local querytab = {}
        for k, v in pairs(query) do
            table.insert(querytab, string.format("%s=%s", escape(k), escape(v)))
        end

        if #querytab > 0 then
            urlfull = path .. "?" .. table.concat(querytab, "&")
        end
    end

    local status, recv_body = httpc.request("POST", host, urlfull, recv_header,
        header, body)

    if status ~= 200 then error("http status " .. status) end

    local ret = json.decode(recv_body)
    if ret.e ~= 0 then
        log("FAULURE %s%s %s", host, urlfull, body)
    else
        -- log("%s%s %s", host, urlfull, body)
    end
    return ret
end

function _M.get(url, query)
    local recv_header = {}
    local host, path = table.unpack(cache[url])

    local urlfull = path
    if query then
        local querytab = {}
        for k, v in pairs(query) do
            table.insert(querytab, string.format("%s=%s", escape(k), escape(v)))
        end

        if #querytab > 0 then
            urlfull = path .. "?" .. table.concat(querytab, "&")
        end
    end

    local status, recv_body = httpc.get(host, urlfull, recv_header, header)
    if status ~= 200 then error("http status " .. status) end

    local ret = json.decode(recv_body)
    if ret.e ~= 0 then
        log("FAULURE %s%s", host, urlfull)
    else
        log("%s%s", host, urlfull)
    end
    return ret
end

return _M
