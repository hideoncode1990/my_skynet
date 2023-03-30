--[[
    对话
]] local stat = require "battle.stat"
local pause = require"battle.global".pause
local stat_push = stat.push

return function(bctx, src, ctx, tobj, ecfg)
    local chatid = ecfg.parm[1]
    pause(bctx, true)
    stat_push(bctx, tobj, "battle_chat", {chatid = chatid})
end
