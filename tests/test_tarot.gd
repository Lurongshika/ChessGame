# 塔罗牌映射自检:godot --headless --path . --script res://tests/test_tarot.gd
extends SceneTree

var _failures := 0


func _initialize() -> void:
	_test_all()
	if _failures == 0:
		print("== ALL TESTS PASSED ==")
	else:
		printerr("== %d TEST(S) FAILED ==" % _failures)
	quit(0 if _failures == 0 else 1)


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  ok - ", name)
	else:
		_failures += 1
		printerr("FAIL - ", name)


func _test_all() -> void:
	var Tarot := preload("res://scripts/tarot.gd")
	var Perks := preload("res://scripts/perks.gd")

	# 44 个技能全部能映射到塔罗牌面且资源存在
	var ids: Array = []
	for row in Perks.PERKS_NORMAL:
		ids.append(row["id"])
	for row in Perks.PERKS_ADVANCED:
		ids.append(row["id"])
	_check(ids.size() == 44, "技能池共 %d 个(正位+逆位)" % ids.size())
	var missing := 0
	for id in ids:
		if Tarot.texture(id) == null:
			missing += 1
			printerr("  missing texture: %s -> %s" % [id, Tarot.texture_path(id)])
	_check(missing == 0, "全部技能牌面资源存在(缺 %d 个)" % missing)

	# 正/逆位判定
	_check(Tarot.is_reversed("yuzhe2") and not Tarot.is_reversed("yuzhe"), "逆位判定(id+2)")
	_check(not Tarot.is_reversed("_cannon_2"), "内部标记键不算逆位")

	# 编号映射(22 张正位一一对应)
	_check(Tarot.card_index("huanghou") == 3 and Tarot.card_index("huanghou2") == 3, "编号映射(皇后=3)")
	_check(Tarot.card_index("shijie") == 21 and Tarot.card_index("shijie2") == 21, "编号映射(世界=21)")
	_check(Tarot.card_index("unknown_skill") == -1, "未知 id 返回 -1")

	# 牌面尺寸比例(408×632)
	var s := Tarot.card_size(200.0)
	_check(absf(s.x / s.y - 408.0 / 632.0) < 0.001, "尺寸比例 408:632(%d×%d)" % [int(s.x), int(s.y)])

	# 卡片控件构建(悬停提示节点可空)
	var card := preload("res://scripts/perk_card.gd").new()
	card.setup("yuzhe2", 0, "愚者·逆位", "主动 · 16回合", "复原所有棋子位置", load("res://fonts/zpix.ttf"), true, 100.0)
	_check(card.get_child_count() >= 1, "塔罗卡构建成功(单张牌面)")
	card.free()

	# 悬浮提示构建
	var tip := preload("res://scripts/tarot_tooltip.gd").new()
	tip.setup(load("res://fonts/zpix.ttf"))
	tip.show_for("huanghou", "皇后", "主动 · 被吃充能1", "所有棋子获得无敌")
	_check(tip.visible and tip.get_child_count() >= 4, "悬浮提示显示(牌图+3 文本)")
	tip.hide_tip()
	_check(not tip.visible and tip.get_child_count() == 0, "悬浮提示隐藏并清理")
	tip.free()
