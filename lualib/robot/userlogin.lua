local httpc = require "http.httpc"
local uurl = require "util.url"
local json = require "rapidjson.c"
local setting = require("setting.factory").proxy("robot")

local function url_login(url, ctx)
    local host, path = uurl.parse(url)
    local header = {["content-type"] = "application/json;charset=UTF-8"}

    local recvheader = {}
    local code, body = httpc.request("POST", host, path, recvheader, header,
        json.encode(ctx))
    assert(code == 200, body)
    return json.decode(body)
end

local function serverlist_get(url)
    local host, path = uurl.parse(url)
    local header = {}
    local code, body = httpc.get(host, path, header)
    assert(code == 200, body)
    return json.decode(body)
end

local function random_table(tbl)
    local len = #tbl
    for i = 1, len do
        local j = math.random(len)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
end

return function(sid, user)
    local serverlist = serverlist_get(setting.serverlist)
    for _, scfg in ipairs(serverlist.g or {}) do
        if scfg[1] == sid then
            local ret = url_login(setting.userlogin, user)
            assert(ret.e == 0, ret.m or "unknow")
            local token = ret.token
            local proxys = serverlist.p or {}
            random_table(proxys)
            return scfg, proxys, token
        end
    end
    error("error sid " .. sid)
end
