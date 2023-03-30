local client = require "client.dispatch"
local socket = require "skynet.socket"

function client.read_message(self)
    local fd = self.fd
    if socket.invalid(fd) then return end
    local s = socket.read(fd, 2)
    if not s then return end
    local len = string.unpack(">H", s)
    return socket.read(fd, len), len
end

function client.start(self, on_warnning)
    socket.start(self.fd)
    socket.warning(self.fd, on_warnning)
end

return client
