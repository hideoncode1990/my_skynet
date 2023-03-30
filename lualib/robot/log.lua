local log = require "log"

return function(self, info)
    do return end
    local opt = info.opt
    info.opt = nil
    local string, tab = string.format("%s(%d) opt:%s; ", self.rname, self.rid,
        opt), {}
    for k, v in pairs(info) do
        string = string .. "%s:%s; "
        table.insert(tab, k)
        table.insert(tab, v)
    end
    string = string .. "\n"
    log(string, table.unpack(tab))
end
