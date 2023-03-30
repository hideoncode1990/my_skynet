local skynet = require "skynet"
local fsm_event = require "battle.fsm.event"
local fsm_state = require "battle.fsm.state"
local log = require "log"
local fsm
local FSM_machine = {}

local function create_transition(s_state, event, t_state)
    local t = FSM_machine[s_state] or {}
    t[event] = t_state
    FSM_machine[s_state] = t
end

skynet.init(function()
    fsm = require "battle.fsm"
    create_transition(fsm_state.idle, fsm_event.moveto, fsm_state.move)
    create_transition(fsm_state.idle, fsm_event.die, fsm_state.dead)
    create_transition(fsm_state.idle, fsm_event.cast, fsm_state.cast)

    create_transition(fsm_state.move, fsm_event.stop_move, fsm_state.idle)
    create_transition(fsm_state.move, fsm_event.die, fsm_state.dead)

    create_transition(fsm_state.cast, fsm_event.cast_failure, fsm_state.idle)
    create_transition(fsm_state.cast, fsm_event.cast_over, fsm_state.idle)
    create_transition(fsm_state.cast, fsm_event.die, fsm_state.dead)

    create_transition(fsm_state.wood, fsm_event.die, fsm_state.dead)
end)

return function(bctx, self, event)
    -- log("%s transition %d->(%d)", self.id, self.FSMstate, event)
    if event <= 0 or event >= fsm_event.max then
        error(string.format("%s(%d) %d->(%d) ", self.id, self.cfgid,
            self.FSMstate, event))
    end
    local s_state = self.FSMstate
    local t = FSM_machine[s_state]
    if not t then
        error(string.format("%s(%d)  %d->(%d) ", self.id, self.cfgid,
            self.FSMstate, event))
    end
    local t_state = t[event]
    if not t_state then
        error(string.format("%s(%d) %d->(%d) ", self.id, self.cfgid,
            self.FSMstate, event))
    end
    fsm.leave(bctx, self, s_state)
    self.FSMstate = t_state
    fsm.enter(bctx, self, t_state)
    return true
end

