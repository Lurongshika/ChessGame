# 技能池:塔罗牌 44 个技能(22 正位 + 22 逆位),属于同一个模式
# 数据内置在代码中(不读 res:// 文件,保证导出版可用)
# 编辑下方 PERKS_NORMAL / PERKS_ADVANCED 即可增删改技能,保存后重启游戏生效。
extends RefCounted

# 技能字段:id(英文,逻辑识别) name tip(类型/触发) desc(描述) cat(分类)
# 普通版技能池(22 个)
const PERKS_NORMAL := [
	{"id": "yuzhe", "name": "愚者", "tip": "主动 · 8回合", "desc": "打乱所有棋子位置(每子75%概率不动)", "cat": "全局"},
	{"id": "moshushi", "name": "魔术师", "tip": "主动 · 6回合", "desc": "交换我方两子的位置", "cat": "全局"},
	{"id": "nvjisi", "name": "女祭司", "tip": "主动 · 3回合", "desc": "所有兵前进一格,并补全己方所有兵", "cat": "全局"},
	{"id": "huanghou", "name": "皇后", "tip": "主动 · 被吃充能1", "desc": "所有棋子获得无敌(持续2回合)", "cat": "全局"},
	{"id": "huangdi", "name": "皇帝", "tip": "主动 · 2回合", "desc": "指定己方一子无敌(持续3回合)", "cat": "全局"},
	{"id": "jiaohuang", "name": "教皇", "tip": "被动 · 象强化", "desc": "以象为中心5×5范围内(除象自身)的己方棋子获得无敌", "cat": "棋子"},
	{"id": "lianren", "name": "恋人", "tip": "被动", "desc": "每被吃两个子可以复活一子到同类棋子出生位置,位置全部被占则不可复活", "cat": "全局"},
	{"id": "zhanche", "name": "战车", "tip": "被动 · 车强化", "desc": "与己方车相邻的棋子,可落至该车所能落位(整局生效)", "cat": "全局"},
	{"id": "zhengyi", "name": "正义", "tip": "被动 · 马强化", "desc": "马不会被别马腿,可跳过阻挡,可跳至另一马所能落位", "cat": "棋子"},
	{"id": "yinzhe", "name": "隐者", "tip": "主动 · 3回合", "desc": "指定己方两子隐身两回合,隐身子无法攻击", "cat": "全局"},
	{"id": "mingyun", "name": "命运之轮", "tip": "主动 · 4回合", "desc": "该回合可额外移动一次(不能连续动同一子)", "cat": "全局"},
	{"id": "liliang", "name": "力量", "tip": "被动", "desc": "我方主动技能充能/冷却-2", "cat": "全局"},
	{"id": "diaodiao", "name": "倒吊人", "tip": "主动 · 2回合", "desc": "使用后跳过本回合,在操控己方棋子和非己方棋子间切换(操控非己方棋子时可吃子)", "cat": "全局"},
	{"id": "siwang", "name": "死亡", "tip": "主动 · 被吃充能2", "desc": "摧毁敌我各一枚指定的同类型子", "cat": "全局"},
	{"id": "jiezhi", "name": "节制", "tip": "主动", "desc": "跳过该回合,下回合己方追加一额外回合", "cat": "全局"},
	{"id": "emo", "name": "恶魔", "tip": "被动", "desc": "敌方无法使用同类型的子连续吃掉我方棋子", "cat": "全局"},
	{"id": "ta", "name": "塔", "tip": "被动 · 开局生效", "desc": "开局额外获得四枚兵;兵从开局即可斜向前吃子(无过河限制)", "cat": "全局"},
	{"id": "xingxing", "name": "星星", "tip": "被动 · 每回合一次", "desc": "每回合一次,兵/卒可无代价移动一格(任意方向,仅空格,不消耗行动)", "cat": "棋子"},
	{"id": "yueliang", "name": "月亮", "tip": "被动 · 象强化", "desc": "象的移动距离不受限制", "cat": "棋子"},
	{"id": "taiyang", "name": "太阳", "tip": "被动 · 车强化", "desc": "车可以斜走一格", "cat": "棋子"},
	{"id": "shenpan", "name": "审判", "tip": "被动", "desc": "随机禁用非己方一个技能", "cat": "全局"},
	{"id": "shijie", "name": "世界", "tip": "被动", "desc": "每回合每个己方棋子都会有25%概率变为任意棋子(将帅除外)", "cat": "全局"},
]

# 进阶版技能池(22 个)
const PERKS_ADVANCED := [
	{"id": "yuzhe2", "name": "愚者·逆位", "tip": "主动 · 16回合(开局无充能)", "desc": "复原所有棋子位置(不复活被吃子);开局需 16 回合充能", "cat": "全局"},
	{"id": "moshushi2", "name": "魔术师·逆位", "tip": "主动 · 6回合", "desc": "交换敌方两子的位置", "cat": "全局"},
	{"id": "nvjisi2", "name": "女祭司·逆位", "tip": "主动 · 7回合", "desc": "在我方底线随机位置生成一个随机棋子(兵和士除外)", "cat": "全局"},
	{"id": "huanghou2", "name": "皇后·逆位", "tip": "主动 · 被吃充能1", "desc": "所有棋子获得反制持续1回合(被吃时与对方同归于尽)", "cat": "全局"},
	{"id": "huangdi2", "name": "皇帝·逆位", "tip": "主动", "desc": "指定己方一子获得反制,效果永久存在(被吃时同归于尽)", "cat": "全局"},
	{"id": "jiaohuang2", "name": "教皇·逆位", "tip": "被动 · 象强化", "desc": "以象为中心5×5范围内(除象自身)的棋子获得反制(被吃时同归于尽)", "cat": "棋子"},
	{"id": "lianren2", "name": "恋人·逆位", "tip": "被动", "desc": "每被吃3个子随机摧毁敌方5子(仅四人模式)", "cat": "全局"},
	{"id": "zhanche2", "name": "战车·逆位", "tip": "被动 · 车强化", "desc": "己方车可落至相邻子(含敌方)所能落位(整局生效)", "cat": "全局"},
	{"id": "zhengyi2", "name": "正义·逆位", "tip": "主动 · 2回合", "desc": "炮吃子变为隔两子,使用技能后在隔一二子间切换", "cat": "棋子"},
	{"id": "yinzhe2", "name": "隐者·逆位", "tip": "主动 · 12回合", "desc": "我方所有子进入隐身;每回合每子10%概率破隐,移动后立刻破隐", "cat": "全局"},
	{"id": "mingyun2", "name": "命运之轮·逆位", "tip": "主动 · 6回合", "desc": "随机两子进入协同状态(不消耗步数)", "cat": "全局"},
	{"id": "liliang2", "name": "力量·逆位", "tip": "被动", "desc": "己方充能达到上限后允许继续充能,最多累计至上限的3倍", "cat": "全局"},
	{"id": "diaodiao2", "name": "倒吊人·逆位", "tip": "主动 · 9回合", "desc": "使用后跳过本回合,下回合起获得所有对方棋子控制权持续三回合(每子每回合限移一次,不能吃子)", "cat": "全局"},
	{"id": "siwang2", "name": "死亡·逆位", "tip": "主动 · 被吃充能2", "desc": "摧毁敌我各随机一子(将帅除外),己方有50%概率免疫摧毁", "cat": "全局"},
	{"id": "jiezhi2", "name": "节制·逆位", "tip": "主动", "desc": "这回合追加一次行动,跳过下回合", "cat": "全局"},
	{"id": "emo2", "name": "恶魔·逆位", "tip": "被动", "desc": "被吃子后,只能被该类型棋子攻击,其他棋子攻击无效,持续2回合", "cat": "全局"},
	{"id": "ta2", "name": "塔·逆位", "tip": "被动 · 开局生效", "desc": "开局失去所有兵;我方所有子可八向移动一格", "cat": "全局"},
	{"id": "xingxing2", "name": "星星·逆位", "tip": "主动 · 0充能", "desc": "使用后跳过该回合,每跳过一回合获得2蓄势;每有1蓄势可免费移动一个兵(允许连续移动同一兵)", "cat": "棋子"},
	{"id": "yueliang2", "name": "月亮·逆位", "tip": "被动 · 象强化", "desc": "象的移动步数不受限制", "cat": "棋子"},
	{"id": "taiyang2", "name": "太阳·逆位", "tip": "被动 · 车强化", "desc": "己方没有炮时,车变为八向无限距离移动", "cat": "棋子"},
	{"id": "shenpan2", "name": "审判·逆位", "tip": "被动", "desc": "敌方无法使用技能吃掉我方棋子,只能使用原版移动吃掉", "cat": "全局"},
	{"id": "shijie2", "name": "世界·逆位", "tip": "被动", "desc": "每回合每个敌方棋子都会有25%概率变为任意棋子(将帅除外)", "cat": "全局"},
]


# 按技能池加载,返回 { id: {name, tip, desc, cat} }
# 全部 44 个技能(22 正位 + 22 逆位)属于同一个模式;pool 参数兼容旧调用
static func load_perks(pool := "all") -> Dictionary:
	var perks := {}
	var rows: Array = []
	if pool == "normal":
		rows = PERKS_NORMAL
	elif pool == "advanced":
		rows = PERKS_ADVANCED
	else:
		rows = PERKS_NORMAL + PERKS_ADVANCED
	for row in rows:
		perks[row["id"]] = {
			"name": row["name"],
			"tip": row["tip"],
			"desc": row["desc"],
			"cat": row["cat"],
		}
	return perks


# 从池子里抽取 count 个不重复的强化
static func draw(count: int, taken: Dictionary, pool := "all") -> Dictionary:
	var pool_data: Array = _pool_rows(pool)
	var ids: Array = []
	for row in pool_data:
		if not taken.has(row["id"]):
			ids.append(row["id"])
	ids.shuffle()
	var result := {}
	for i in mini(count, ids.size()):
		result[ids[i]] = true
	return result


# 三选一:从池子返回 count 个选项(id 数组,与已选不重复)
static func draw_options(count: int, taken: Dictionary, pool := "all") -> Array:
	var pool_data: Array = _pool_rows(pool)
	var ids: Array = []
	for row in pool_data:
		if not taken.has(row["id"]):
			ids.append(row["id"])
	ids.shuffle()
	var result: Array = []
	for i in mini(count, ids.size()):
		result.append(ids[i])
	return result


static func _pool_rows(pool: String) -> Array:
	if pool == "normal":
		return PERKS_NORMAL
	if pool == "advanced":
		return PERKS_ADVANCED
	return PERKS_NORMAL + PERKS_ADVANCED


# 四人模式选技能:从 44 个抽取 32 个,分为 4 组(每组 8 个),
# 同一张卡的正/逆位不会出现在同一组内。返回 [[8个id], [8个id], [8个id], [8个id]]
static func build_four_pools(pool := "all") -> Array:
	var rows: Array = _pool_rows(pool)
	var all_ids: Array = []
	for row in rows:
		all_ids.append(row["id"])
	all_ids.shuffle()
	# 抽 32 个
	var picked: Array = []
	for i in mini(32, all_ids.size()):
		picked.append(all_ids[i])
	# 分组:正逆位不同组
	# 先把 32 个按"对"归类:正位 id → 逆位 id(正位+2),逆位 id → 正位 id
	var base_of := {}
	for id in picked:
		if id.length() > 1 and id.ends_with("2") and not id.ends_with("_2"):
			base_of[id] = id.substr(0, id.length() - 1)
		else:
			base_of[id] = id
	# 对每个 base 收集成员
	var groups_by_base := {}
	var bases := []
	for id in picked:
		var b: String = base_of[id]
		if not groups_by_base.has(b):
			groups_by_base[b] = []
			bases.append(b)
		groups_by_base[b].append(id)
	# 分配:完整对(2 个)分到两个不同组;单张分到当前最少组
	var groups := [[], [], [], []]
	for b in bases:
		var members: Array = groups_by_base[b]
		if members.size() >= 2:
			# 正逆位分到两个不同组(选当前成员数最少的两个不同组)
			var g1 := _min_group_index(groups, -1)
			var g2 := _min_group_index(groups, g1)
			groups[g1].append(members[0])
			groups[g2].append(members[1])
		else:
			var g := _min_group_index(groups, -1)
			groups[g].append(members[0])
	# 均衡兜底:某组超 8 则移到最少组(一般不会发生,32/4=8 恰好)
	for g in 4:
		while groups[g].size() > 8:
			var target := _min_group_index(groups, -1)
			if target == g:
				break
			groups[target].append(groups[g].pop_back())
	return groups


static func _min_group_index(groups: Array, exclude: int) -> int:
	var best := -1
	for i in groups.size():
		if i == exclude:
			continue
		if best < 0 or groups[i].size() < groups[best].size():
			best = i
	return best if best >= 0 else 0
