local net = require "robot.net"
return function(self, content)
    net.request(self, nil, 'chat_chating', {content = content})
end