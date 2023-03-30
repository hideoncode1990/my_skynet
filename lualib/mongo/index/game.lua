local skynet = require "skynet"
local cfgproxy = require "cfg.proxy"

local cfg = {
    DB_GAME = {
        activity = {{"name", unique = true}},
        emails = {{"id", unique = true}, {"target"}, {"time"}},
        player = {
            {"uid", "sid", unique = true}, {"rid", unique = true}, {"sid"}
        },
        roleinfo = {{"rid", unique = true}},
        variable = {{"key", unique = true}},
        payorder = {{"order", unique = true}},
        paybillno = {{"order", unique = true}},
        solo = {{"rid", unique = true}},
        forbidden = {{"rid", unique = true}},
        report_ml = {{"rid", "mainline", unique = true}},
        report_sl = {{"replayid", unique = true}},
        replay = {{"uuid", unique = true}, {"ti"}},
        rid_counter = {{"sid", unique = true}},
        arena_stage = {{"rid", unique = true}},
        arena_rank = {{"rid", unique = true}},
        solo_record = {{"rid", unique = true}},
        arena_record = {{"rid", unique = true}},
        userflag = {{"uid", unique = true}},
        legion_trial = {{"rid", unique = true}},
        explore = {{"owner", unique = true}}
    },
    DB_LOG = {login = {{"uuid", unique = true}}}
}

for _, tp in pairs(require "zset.type") do
    cfg.DB_GAME["zset_" .. tp] = {{"id", unique = true}}
end

local SOLO
skynet.init(function()
    SOLO = cfgproxy("solo")
    for i = 1, SOLO.group do
        cfg.DB_GAME["zset_" .. (i + 1000)] = {{"id", unique = true}}
    end
end)

return cfg

-- order 排序，1为升序，-1为降序。顺序默认1
-- unque 建立的索引是否唯一。指定为true创建唯一索引。默认值为false.
-- background 建索引过程阻塞其它数据库操作，background可指定以后台方式创建索引，true为后
-- 台，默认值为false
-- name 索引的名称。默认为通过连接索引的字段名和排序顺序生成一个索引名称。
