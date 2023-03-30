local transition = require "battle.fsm.transition"
local fsm_state = require "battle.fsm.state"
local b_util = require "battle.util"
local profile = require "battle.profile"
local profile_add = profile.add
local _M = {}
local camp_type = require "battle.camp_type"
local function log(bctx, self, ...)
    if self.camp == camp_type.left then b_util.log(bctx, ...) end
end

function _M.enter(bctx, self, state)
    if state == fsm_state.cast then self:fsm_enter_cast(bctx) end
end

function _M.leave(bctx, self, state)
    -- body
end

local fsm_cb = {
    [fsm_state.idle] = function(bctx, self)
        self:fsm_idle(bctx)
    end,
    [fsm_state.move] = function(bctx, self)
        self:fsm_move(bctx)
    end,
    [fsm_state.cast] = function(bctx, self)
        self:fsm_cast(bctx)
    end,
    [fsm_state.wood] = function(bctx, self)
    end,
    [fsm_state.dead] = function(bctx, self)
        self:fsm_dead(bctx)
    end
}

function _M.update(bctx, self)
    local state = self.FSMstate
    -- fsm_cb[state](bctx, self)
    ---[[
    if state == fsm_state.idle then
        self:fsm_idle(bctx)
    elseif state == fsm_state.move then
        self:fsm_move(bctx)
    elseif state == fsm_state.cast then
        self:fsm_cast(bctx)
    elseif state == fsm_state.dead then
        self:fsm_dead(bctx)
        -- elseif state == fsm_state.wood then
    end
    -- ]]
end

_M.transition = transition

return _M

