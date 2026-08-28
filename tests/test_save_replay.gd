# 存档/复盘集成测试:godot --headless --path . --script res://tests/test_save_replay.gd -- --mode=pvp
extends SceneTree

var _failures := 0


func _initialize() -> void:
	_run()


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  ok - ", name)
	else:
		_failures += 1
		printerr("FAIL - ", name)


func _board_sig(b: Array) -> String:
	var s := ""
	for row in b:
		for p in row:
			s += "." if p == null else "%d%d" % [p["side"], p["type"]]
	return s


func _cleanup_saves() -> void:
	for i in range(1, 4):
		var path := "user://savegame_%d.json" % i
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _run() -> void:
	var R := preload("res://scripts/chess_rules.gd")
	var AI := preload("res://scripts/ai.gd")
	_cleanup_saves()

	# 场景1:正常对局,走几步(每步自动存档到第一个空槽)
	var scene = load("res://scenes/game.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene._start_game()
	_check(scene.current_slot == 1, "新对局自动分配到槽 1")
	_check(FileAccess.file_exists("user://savegame_1.json"), "开局自动存档已写入")
	for i in 6:
		var side: int = R.Side.RED if i % 2 == 0 else R.Side.BLACK
		var mv := AI.choose_move(scene.board, side, scene.perks_red, scene.perks_black)
		if mv.is_empty():
			break
		scene._try_perform(mv["from"], mv["to"], "move")
		await process_frame
	_check(scene.move_history.size() >= 3, "走子记录已生成(%d 步)" % scene.move_history.size())
	_check(FileAccess.file_exists("user://savegame_1.json"), "走子后自动存档仍在")
	var saved_board := _board_sig(scene.board)
	var saved_turn: int = scene.turn
	var saved_moves: int = scene.move_history.size()

	# 场景2:加载槽 1(新实例)
	scene.queue_free()
	await process_frame
	root.get_node("Global").load_slot = 1
	var scene2 = load("res://scenes/game.tscn").instantiate()
	root.add_child(scene2)
	await process_frame
	_check(scene2.phase == scene2.Phase.PLAY, "加载后进入对局")
	_check(scene2.current_slot == 1, "加载后绑定槽 1")
	_check(scene2.move_history.size() == saved_moves, "加载后走子记录一致")
	_check(_board_sig(scene2.board) == saved_board, "加载后棋盘一致")
	_check(scene2.turn == saved_turn, "加载后回合一致")

	# 复盘:从头回放
	scene2._start_replay()
	_check(scene2.replay_mode, "进入复盘模式")
	_check(scene2.replay_index == 0, "复盘从第 0 步开始")
	for i in saved_moves:
		scene2._replay_next()
	_check(scene2.replay_index == saved_moves, "复盘步数完整")
	_check(_board_sig(scene2.replay_board) == _board_sig(scene2.board), "复盘最终棋盘与实盘一致")
	scene2._replay_prev()
	_check(scene2.replay_index == saved_moves - 1, "上一步有效")
	scene2._exit_replay()
	_check(not scene2.replay_mode, "退出复盘正常")

	# 清理存档
	_cleanup_saves()

	if _failures == 0:
		print("== SAVE & REPLAY OK ==")
	else:
		printerr("== %d CHECK(S) FAILED ==" % _failures)
	quit(0 if _failures == 0 else 1)
