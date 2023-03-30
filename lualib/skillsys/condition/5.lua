-- 指定技能类型
local get_scfg = require"skillsys.skill_sys".get_scfg
return function(bctx, self, tobj, ctx, parm)
    if self.id == ctx.caster then
        local _type = parm[1]
        local skill_cfg = get_scfg(ctx.skillid)
        if skill_cfg and skill_cfg.skilltype == _type then return true end
    end
    return false
end
