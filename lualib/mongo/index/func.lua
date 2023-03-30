return {
    DB_FUNC = {
        activity = {{"name", unique = true}},
        rnamesync = {{"rid", unique = true}, {"rname"}, {"sid"}},
        guild = {{"gid", unique = true}, {"gname", unique = true}, {"sid"}},
        guildrole = {
            {"rid", unique = true}, {"gid"}, {"rid", "gid", unique = true},
            {"rid", "gid", "punish_quit_ti", unique = true}
        },
        guildapply = {{"rid"}, {"gid"}, {"rid", "gid", unique = true}},
        report_guildboss = {{"uuid", unique = true}},
        func_lock = {{"key", unique = true}}
    }
}
