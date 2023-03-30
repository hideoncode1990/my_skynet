-- local skynet = require "skynet"
-- local net = require "robot.net"
local bag = require "robot.bag"
local chat = require "robot.chat"

local NEED = {
    {5, 10002, 999}, -- 进化模块 用于进化的材料
    {5, 10016, 999}, -- 高级竞技挑战券 用于进化的材料
    {5, 10008, 999}, -- 单人竞技挑战券 用于进化的材料
    {1, 0, 9999999999}, -- 钻石
    {2, 0, 9999999999} -- 金币
}

local function material_check(self, tab)
    local ok, tp, id, cnt, has_cnt = bag.checkdel_one(self, tab)
    if ok then return end
    if not tp then
        return tab
    else
        return {tp, id, cnt - has_cnt}
    end
end

local function prepare_materials(self)
    for _, v in ipairs(NEED) do
        local need = material_check(self, v)
        if need then
            chat(self,
                string.format("lua@item(%d,%d,%d)", need[1], need[2], need[3]))
        end
    end
end

return {
    onlogin = function(self)
        prepare_materials(self)
    end
}
