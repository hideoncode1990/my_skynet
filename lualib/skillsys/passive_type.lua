return {
    global_init = 101, -- 全局被动初始化
    init = 0, -- 开始战斗时
    before_attack = 1, -- 对目标进行伤害计算之前
    after_attack = 2, -- 对目标进行伤害结算之后
    before_hurt = 3, -- 受到伤害计算之前
    after_hurt = 4, -- 受到伤害结算之后
    start_cast = 5, -- 开始施法时
    cast_over = 6, -- 施法结束后(正常结束)
    be_cast_start = 7, -- 别人开始对自己释放技能时
    hp_change = 8, -- 自身血量变化时
    near_dead = 9, -- 自己濒死时
    dead = 10, -- 死亡时
    kill = 11, -- 击杀时
    no_hurt = 12, -- 免疫伤害时
    no_control = 13, -- 免疫控制时

    friend_hero_change = 15, -- 友方英雄数量变化(开始战斗时、死亡时)
    give_signet = 16, -- 给目标添加印记时
    get_signet = 17, -- 获得印记时
    overhp = 18, -- 过量治疗时
    beadd_buff = 19, -- 被施加buff时
    enemy_hero_change = 20, -- 敌方英雄数量变化(开始战斗时、死亡时)
    first_use_combo_enemy = 21, -- 敌方第一次释放combo时(伤害之前)
    t_hp_change = 22, -- 目标血量变化时
    first_use_combo = 23, -- 首次使用必杀技
    heal = 24, -- 治疗目标时
    attr_attack = 25, -- 计算伤害时获得临时属性(攻击时)
    attr_hurt = 26, -- 计算伤害时获得临时属性(被攻击时)
    attr_heal = 27, -- 计算治疗量时获得临时属性(治疗前)
    buff_over = 28, -- buff结束时
    hpchg_next_frame = 29 -- 血量变化时下一帧触发
}
