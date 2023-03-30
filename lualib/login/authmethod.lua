local crypt = require "skynet.crypt"
local checksum = require "checksum"
local ustring = require "util.string"
local json = require "rapidjson.c"
local skynet = require "skynet"
local gamecenter = require "gamecenter"

local tokentable
skynet.init(function()
    local ret = gamecenter.get("/interface/user/token")
    assert(ret.e == 0)
    tokentable = ret.list
end)

local safe_revert = {['-'] = '+', ['_'] = '/'}
local function base64url_decode(s)
    s = (string.gsub(s, '[-_]', safe_revert))
    local more = (#s) & 0x3
    if more > 0 then s = s .. string.rep('=', 4 - more) end
    return crypt.base64decode(s)
end

local safe = {['='] = '', ['+'] = '-', ['/'] = '_'}
local function base64url_encode(s)
    return (string.gsub(crypt.base64encode(s), '[=+/]', safe))
end

local _M = {}

function _M.check(token)
    local eheader, epayload, sign = ustring.splitrow(token, ".")
    local ok, err
    ok, err = pcall(base64url_decode, epayload)
    if not ok then return 1, err end

    ok, err = pcall(json.decode, err)
    if not ok then return 2, err end

    local payload = err
    local i = payload.i
    if not i then return 3, "no i" end
    local secret = tokentable[(i % #tokentable) + 1]
    if not secret then return 3, "error i " .. i end
    local data = eheader .. "." .. epayload
    local selfsign = base64url_encode(checksum.hmac_sha256(secret, data))
    if selfsign ~= sign then return 4, "error sign" end
    local expired_ti = payload.iat + 300
    if expired_ti < skynet.time() then return 9, "timeout" end

    return 0, payload
end

return _M
