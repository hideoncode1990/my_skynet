local skynet = require "skynet"
local bootstrap = require "boot"
local env = require "env"

-- 读取进程配置服务
bootstrap.open_setting()
-- 启动基础服务
bootstrap.open_base()
-- sproto协议初始化
bootstrap.open_sproto()
-- 配置初始化
bootstrap.open_cfg()

if env.opts_cfgcheck then -- 配置检查
    bootstrap(skynet.newservice, "game/cfgcheck")
end

-- client control
bootstrap(skynet.uniqueservice, "game/clientcontrol")

-- 流水日志初始化
require "flowlog.bootstrap.game"
-- 平台日志初始化
if env.enable_platlog == "true" then require "platlog.bootstrap.game" end
if env.enable_taptap == "true" then
    bootstrap(skynet.uniqueservice, "game/platlog/heartd")
end

-- 启动公会服务
bootstrap(skynet.uniqueservice, "game/guild")

bootstrap(skynet.uniqueservice, "game/webcfg")

bootstrap(skynet.uniqueservice, "base/zsetmgr")
bootstrap(skynet.uniqueservice, "game/payd")
bootstrap(skynet.uniqueservice, "game/emailwatcher")
bootstrap(skynet.uniqueservice, "game/roleinfoagent")
bootstrap(skynet.uniqueservice, "game/accounts")

-- 打开内部通信
bootstrap.open_cluster()

-- 打开游戏监听
bootstrap(skynet.uniqueservice, "game/bootlast")

local ustring = require "util.string"
local parallels = require "parallels"
bootstrap(function()
    local list = ustring.split(env.bootparams)
    local pa = parallels()
    for _, s in ipairs(list) do
        pa:add(function()
            skynet.error("Boot", s)
            local addr = skynet.newservice(s)
            pcall(skynet.call, addr, "debug", "LINK")
        end)
    end
    pa:wait()
end)

skynet.start(function()
    bootstrap.main()
    skynet.exit()
end)
