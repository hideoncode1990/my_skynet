local skynet = require "skynet"
local utime = require "util.time"
local chattype = require "chat.type"
local cfgproxy = require "cfg.proxy"
local log = require "log"
local words = require "words"
local client = require "client"
local fnopen = require "role.fnopen"
local friend = require "role.m_friend"
local cache = require("mongo.role")("chat")
local roleid = require "roleid"
local _LUA = require "handler.lua"
local _H = require "handler.client"
local env = require "env"

local NM<const> = "chat"
local CHANNEL_SPECIAL<const> = 0

local chatd, cmd, forbidden, CFG_COM, guildproxy

local function enter(self)
    local channel
    if fnopen.check_open(self, NM) then
        channel = cache.get(self).channel or CHANNEL_SPECIAL
    end
    skynet.call(chatd, "lua", "enter", self.rid, self.fd, skynet.self(), channel)
end

skynet.init(function()
    cmd = skynet.uniqueservice("game/cmd")
    chatd = skynet.uniqueservice("game/chatd")
    forbidden = skynet.uniqueservice("game/forbidden")
    guildproxy = skynet.uniqueservice("guild/proxy")
    CFG_COM = cfgproxy("talk_common")
    fnopen.reg(NM, NM, function(self)
        if self.online then enter(self) end
    end)
end)

local shut_up
require("role.mods") {
    name = NM,
    load = function(self)
        shut_up = skynet.call(forbidden, "lua", "forbidden_query", self.rid)
    end,
    enter = enter,
    afk = function(self)
        skynet.call(chatd, "lua", "afk", self.rid)
    end
}

local function generate_data(self, msg)
    return {
        type = msg.type,
        rname = self.rname,
        head = self.head,
        rid = self.rid,
        sid = self.sid,
        content = words.dirtyfilter(msg.content),
        time = utime.time_int()
    }
end

local space = {}
local function check_space(tpnm)
    local cfg = CFG_COM["talk_space_" .. tpnm]
    local now = utime.time()
    if now - (space[tpnm] or 0) >= cfg then return true end
end
local function save_space(tpnm, time)
    space[tpnm] = time
end

local FUNC = {
    [chattype.personal] = function(self, data, msg)
        if friend.check_black(self, msg.rid) then return false, 105 end
        return skynet.call(chatd, "lua", "chat_personal", data, msg.rid,
            roleid.getsid(msg.rid))
    end,
    [chattype.native] = function(_, data)
        skynet.send(chatd, "lua", "chat_native", data)
        return true
    end,
    [chattype.world] = function(_, data)
        return skynet.call(chatd, "lua", "chat_world", data)
    end,
    [chattype.guild] = function(self, data)
        return skynet.call(guildproxy, "lua", "chat_guild", self.rid, data)
    end
}

function _LUA.chat_ask_channel(self)
    return cache.get(self).channel
end

function _LUA.chat_reenter(self, channel, chnmax, contents)
    local C = cache.get(self)
    if channel then
        if channel ~= C.channel then
            C.channel = channel
            cache.dirty(self)
        end
        client.push(self, "chat_world_info",
            {channel = channel, contents = contents, chnmax = chnmax})
    end
end

function _LUA.forbidden_set(_, time)
    shut_up = time
end

function _LUA.chat_reged(self, channel)
    cache.get(self).channel = channel
    cache.dirty(self)
end

function _H.chat_chating(self, msg)
    local content = msg.content
    if env.enable_cmd == "true" then
        local ok, code, body = skynet.call(cmd, "lua", "agent_comand", self.rid,
            content)
        if ok then
            -- log("cmd: %s return %s %s", content, code, json.encode(body))
            return {e = 0, data = {content = body and body.m}}
        end
    end
    if not msg.type then return {e = 3} end
    if shut_up and shut_up >= utime.time_int() then return {e = 1001} end
    if not fnopen.check_open(self, NM) then return {e = 1} end

    local tpnm = assert(chattype[msg.type])
    if not check_space(tpnm) then return {e = 2} end

    local len = utf8.len(content)
    if len <= 0 or len > CFG_COM.word_limit then return {e = 3} end

    local _ok, err = FUNC[msg.type](self, generate_data(self, msg), msg)
    if not _ok then return {e = err} end

    save_space(tpnm, utime.time())
    return {e = 0, data = err}
end

function _H.chat_channel_list(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local channel = msg.channel
    assert(channel > 0)
    local list = skynet.call(chatd, "lua", "chat_channel_list", channel)
    if not list then return {e = 2} end
    return {e = 0, list = list}
end

function _H.chat_channel_change(self, msg)
    if not fnopen.check_open(self, NM) then return {e = 1} end
    local tar = msg.channel
    assert(tar > 0)
    local C = cache.get(self)
    if C.channel == tar then return {e = 2} end

    if not skynet.call(chatd, "lua", "chat_channel_change", self.rid, tar) then
        return {e = 3}
    end
    return {e = 0}
end

function _H.ping(_, msg)
    msg.e = 0
    msg.time = utime.time()
    return msg
end
