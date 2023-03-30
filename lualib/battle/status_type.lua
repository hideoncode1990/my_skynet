return {
    god = 1,
    dead = 2,

    no_choose = 1001, -- 不能被选中
    no_skill_1 = 1002, -- 不能普攻(类型1)
    no_skill_2_3 = 1003, -- 不能释放技能(类型2，3)
    no_skill_2 = 1003,
    no_skill_3 = 1003,
    attack_friend = 1005, -- 攻击友方
    attack_all = 1006, -- 不分敌我
    no_move = 1007, -- 不能移动
    rand_move = 1008, -- 随机移动
    no_control = 1009, -- 免控
    no_hurt = 1010, -- 免伤
    move_slowly = 1011, -- 减速
    move_quickly = 1012, -- 加速
    attack_slowly = 1013, -- 减速
    attack_quickly = 1014, -- 加速
    no_beatback = 1015, -- 不能被击退
    no_heal = 1016, -- 不能治疗
    in_dead = 1017 -- 状态结束后立即死亡(结算时判定为死亡)
}
