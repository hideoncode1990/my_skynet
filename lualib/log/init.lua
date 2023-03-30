local skynet = require "skynet"
return function(...)
    if select("#", ...) == 1 then
        skynet.error(...)
    else
        skynet.error(string.format(...))
    end
end
