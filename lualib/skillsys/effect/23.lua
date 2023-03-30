--[[
    替换指定技能
]] local skillsys = require "skillsys.skill_sys"
local replace_skill = skillsys.replace_skill
local exist_skill = skillsys.exist_skill

return function(bctx, src, ctx, tobj, ecfg)
    local base_ids = ecfg.parm
    local tar_ids = ecfg.parm2
    for i, base_skillid in ipairs(base_ids) do
        if exist_skill(tobj, base_skillid) then
            local tar_skillid = tar_ids[i]
            replace_skill(bctx, tobj, base_skillid, tar_skillid)
        end
    end
end
