local skynet = require "skynet"
local cluster = require "skynet.cluster"
local json = require "rapidjson.c"
local factory = require "setting.factory"
local uurl = require "util.url"
local httpc = require "http.httpc"
local env = require "env"

local node = env.node

local _M = {}

local function remote_access(host, path)
    local header = {}
    skynet.error(host .. path)
    local code, body = httpc.get(host, path, header)
    assert(code == 200, body)
    return json.decode(body)
end

local function groupby(clusters)
    local ret = {}
    for name in pairs(clusters) do
        local match = string.match(name, "([%w]+)_(%d+)$")
        if match then
            local grp = ret[match]
            if not grp then
                grp = {}
                ret[match] = grp
            end
            grp[name] = true
        end
    end
    for _, grp in pairs(ret) do table.sort(grp) end
    return ret
end

local function init_rs(dbs)
    for _, args in ipairs(dbs or {}) do
        local rs = {}
        for k, v in ipairs(args.hosts) do
            local arg = {host = v.host, port = v.port}
            if k == 1 then
                arg.username = args.username
                arg.password = args.password
                arg.authmod = args.authmod
                arg.authdb = args.authdb
            end
            table.insert(rs, arg)
        end
        args.rs = rs
    end
end

function _M.init_setting(setting_host)
    setting_host = setting_host or env.setting_host

    local name = string.format("%s.json", node)
    local setting = remote_access(uurl.parse(setting_host, name))
    init_rs(setting.dbs)
    factory.load("setting", setting)
end

function _M.init_clusters(setting_host)
    setting_host = setting_host or env.setting_host

    local nodes = remote_access(uurl.parse(setting_host, 'nodes.json'))
    local clusters, clusters_node = {}, {}
    for name, info in pairs(nodes) do
        local addr = info.addr
        clusters_node[name] = true
        for _, nm in ipairs(info.list) do clusters[nm] = addr end
    end
    factory.load("clusters", clusters)
    factory.load("clusters_node", clusters_node)
    for nm, grp in pairs(groupby(nodes)) do
        factory.load("clusters_" .. nm, grp)
    end

    clusters.__nowaiting = true
    cluster.reload(clusters)
end

function _M.init()
    local setting_host = env.setting_host

    _M.init_setting(setting_host)
    _M.init_clusters(setting_host)
end

function _M.opencluster()
    cluster.open(node)
end

return _M
