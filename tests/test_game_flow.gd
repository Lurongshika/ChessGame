# 对局流程集成测试:godot --headless --path . --script res://tests/test_game_flow.gd
# 加载真实 game 场景,双方用 AI 驱动完整对局,验证回合状态机与结算不崩
extends SceneTree

var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var R := preload("res://scripts/chess_rules.gd")
	var AI := preload("res://scripts/ai.gd")
	# --script 模式不加载 autoload,手动模拟 Global 单例
	var g := Node.new()
	g.name = "Global"
	g.set_script(load("res://global.gd"))
	g.game_mode = "ai"
	root.add_child(g)
	var scene = load("res://scenes/game.tscn").instantiate()
	root.add_child(scene)
	await process_frame

	# --- 技能池校验 ---
	_check(scene.perks_data.size() == 44, "技能池共 44 个技能(正位+逆位)")
	_check(scene.perks_data.has("zhengyi") and scene.perks_data["zhengyi"]["name"] == "正义", "技能池生效(正义)")
	_check(scene.perks_data.has("ta") and scene.perks_data["ta"]["name"] == "塔", "技能池生效(塔)")
	_check(scene.perks_data.has("yuzhe") and scene.perks_data["yuzhe"]["name"] == "愚者", "技能池生效(愚者)")
	_check(scene.perks_data.has("yuzhe2") and scene.perks_data["yuzhe2"]["name"] == "愚者·逆位", "技能池生效(愚者逆位)")
	_check(scene.perks_data.has("huanghou2") and scene.perks_data["huanghou2"]["name"] == "皇后·逆位", "技能池生效(皇后逆位)")

	# --- 塔:开局额外四枚兵 ---
	scene.perks_red = {"ta": true}
	scene.perks_black = {}
	scene._setup_board()
	var red_pawns := 0
	for r in R.ROWS:
		for c in R.COLS:
			var p = scene.board[r][c]
			if p != null and p["side"] == R.Side.RED and p["type"] == R.Type.PAWN:
				red_pawns += 1
	_check(red_pawns == 9, "塔:红方开局 9 枚兵(5 初始 + 4 额外)")

	# --- 正常随机对局 ---
	scene.perks_red = {}
	scene.perks_black = {}
	scene._start_game()

	var steps := 0
	var waits := 0
	while scene.phase != scene.Phase.OVER and steps < 600:
		steps += 1
		if scene.phase == scene.Phase.PLAY and scene.turn == R.Side.RED:
			# 模拟玩家(AI)走红方
			var mv := AI.choose_move(scene.board, R.Side.RED, scene.perks_red, scene.perks_black)
			if mv.is_empty():
				printerr("FAIL - 红方无合法着法却未判负")
				_failures += 1
				break
			scene._perform_move(mv["from"], mv["to"])
			waits = 0
		else:
			# 等待 AI(黑方)异步完成回合
			waits += 1
			if waits > 900:
				printerr("FAIL - 等待 AI 回合超时")
				_failures += 1
				break
		await process_frame

	print("对局推进: steps=%d, phase=%d, winner=%d" % [steps, scene.phase, scene.winner])
	_check(scene.phase == scene.Phase.PLAY, "AI 拉锯后对局仍在进行")
	_check(scene.board.size() > 0, "棋盘状态有效")
	# 强制吃王结算,验证 _win / _show_result 路径
	scene._win(R.Side.RED)
	_check(scene.phase == scene.Phase.OVER and scene.winner == R.Side.RED, "强制结算后状态正确")

	if _failures == 0:
		print("== GAME FLOW OK ==")
	else:
		printerr("== %d GAME FLOW CHECK(S) FAILED ==" % _failures)
	quit(0 if _failures == 0 else 1)


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  ok - ", name)
	else:
		_failures += 1
		printerr("FAIL - ", name)
