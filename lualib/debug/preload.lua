local debug_traceback = debug.traceback
_G.debug.traceback = require "trace.c"
_G.debug.debug_traceback = debug_traceback
-- if _G.SERVICE_NAME == "robot/agent" then require "debug.replaceloader"({"#1#"}) end
