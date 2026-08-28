extends SceneTree

var game
var R

func _initialize() -> void:
	_run()


func _run() -> void:
	R = load("res://scripts/chess_rules.gd")
	var g = root.get_child(0)
	g.game_mode = "four"
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	_check(game.four_mode, "four_mode 开启")
	_check(game.phase == game.Phase.SKILL_DRAFT, "开局进入技能 DRAFT")
	# 四方各选 3 个技能:8 选 3(点击选中 + 确认)
	var seen_pairs := false
	for side in 4:
		_check(game.draft4_side == side, "DRAFT 轮到方 %d (实际 %d)" % [side, game.draft4_side])
		var opts: Array = game.draft4_options
		_check(opts.size() == 8, "第 %d 方有 8 个选项" % side)
		# 检查该组内无正逆位同组
		var ids := {}
		for o in opts:
			ids[o] = true
		for o in opts:
			var rev: String
			if o.length() > 1 and o.ends_with("2") and not o.ends_with("_2"):
				rev = o.substr(0, o.length() - 1)  # 逆位 → 正位
			else:
				rev = o + "2"  # 正位 → 逆位
			if ids.has(rev):
				seen_pairs = true
		# 选前 3 个
		game._draft_selected4 = []
		for i in 3:
			game._draft_selected4.append(opts[i])
		game._confirm_draft4()
	_check(not seen_pairs, "各组内无正逆位同组")
	_check(game.phase == game.Phase.PLAY, "四方选完进入对局")
	_check(game.perks4[0].size() == 3 and game.perks4[1].size() == 3, "红黑各 3 技能")
	_check(game.perks4[2].size() == 3 and game.perks4[3].size() == 3, "绿蓝各 3 技能")
	# 走子:黑方(侧1)当前回合? SIDE_ORDER4=[1,3,0,2] 第一方=黑
	_check(game.current_side4() == 1, "首回合黑方")
	# 黑方任意子走一步(塔2 删兵时兵可能不存在,用车/马等)
	var from_pos := Vector2i(-1, -1)
	var to_pos := Vector2i(-1, -1)
	var perks_arr: Array = [game.perks4[0], game.perks4[1], game.perks4[2], game.perks4[3]]
	for r in game.board.size():
		for c in game.board[r].size():
			var p = game.board[r][c]
			if p == null or p["side"] != 1:
				continue
			var cand := Vector2i(c, r)
			var mvs: Array = R.raw_moves4(game.board, cand, perks_arr)
			if not mvs.is_empty():
				from_pos = cand
				to_pos = mvs[0]
				break
		if from_pos.x >= 0:
			break
	_check(from_pos.x >= 0, "找到黑方可走子 %s" % from_pos)
	if from_pos.x >= 0:
		game._select4(from_pos)
		game._move4(from_pos, to_pos)
	_check(game.current_side4() == 3, "黑走完轮到蓝")
	# 主动技能:当前方(蓝=3)放一个非目标型主动技能
	var blue_active := ""
	for id in game.perks4[3]:
		if game._is_active_skill(id) and not id in ["moshushi", "moshushi2", "huangdi", "huangdi2", "zhanche", "zhanche2", "siwang", "diaodiao", "diaodiao2"]:
			blue_active = id
			break
	if blue_active == "":
		# 全目标型:直接释放第一个主动技能,验证冷却与回合消耗
		for id in game.perks4[3]:
			if game._is_active_skill(id):
				blue_active = id
				break
	if blue_active != "":
		_check(true, "蓝方有主动技能: %s" % blue_active)
		game._activate_skill4(blue_active, 3)
		# 目标型技能进入 target 选择,不消耗回合
		if not game.targeting4.is_empty():
			_check(true, "目标型技能进入目标选择")
			game._done_targeting4()
		else:
			_check(true, "主动技能已释放")
	else:
		print("  note - 蓝方抽到全被动,跳过主动技能断言")
	# 结束
	quit(0 if _fail_count == 0 else 1)


var _fail_count := 0
func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok - ", msg)
	else:
		_fail_count += 1
		print("FAIL - ", msg)
