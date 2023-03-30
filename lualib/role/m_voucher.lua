local skynet = require "skynet"
local award = require "role.award"
local uaward = require "util.award"
local _H = require "handler.client"
local cache = require("mongo.role")("voucher")
local lock = require "skynet.queue"()
local flowlog = require "flowlog"

local NM<const> = "voucher"
local voucherd
skynet.init(function()
    voucherd = skynet.uniqueservice("game/voucherd")
end)

local function get(self, voucher)
    local C = cache.get(self)

    if C[voucher] then return {e = 3} end
    local ok, reward, code = skynet.call(voucherd, "lua", "voucher_get",
        self.game_channel, self.rid, voucher)

    if not ok then return {e = reward} end
    if C[code] then return {e = 3} end

    C[code] = true
    cache.dirty(self)
    flowlog.role(self, NM, {voucher = code})

    award.adde(self, {
        flag = "voucher_get",
        arg1 = voucher,
        theme = "VOUCHER_FULL_THEME",
        content = "VOUCHER_FULL_CONTENT"
    }, reward)
    return {e = 0, items = uaward.pack(reward)}
end

function _H.voucher_get(self, msg)
    return lock(get, self, assert(msg.voucher))
end
