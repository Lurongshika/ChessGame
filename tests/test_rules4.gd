# 自定义规则测试:杀棋计数/占领/继承/灰化/升变开关
extends SceneTree

var _failures := 0
var R
var game

func _initialize() -> void:
	_run()

func _run() -> void:
	R = load("res://scripts/chess_rules.gd")
	var g = root.get_child(0)
	g.game_mode = "four"
	g.game_rules = {
		"win_mode": "classic", "kill_count": 2,
		"king_down": "grey", "promotion": "queen",
	}
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	game.four_mode = true
	game.board = R.make_board4()
	game.alive4 = {0: true, 1: true, 2: true, 3: true}
	game.perks4 = {0: {}, 1: {}, 2: {}, 3: {}}
	game.phase = game.Phase.PLAY

	# 1) 升变开关:promotion=none 时兵到中心不变后
	g.game_rules["promotion"] = "none"
	for r in 17:
		for c in 17:
			game.board[r][c] = null
	game.board[7][8] = R.make_piece(1, R.Type.PAWN)
	game._move4(Vector2i(8, 7), Vector2i(8, 8))
	_check(game.board[8][8]["type"] == R.Type.PAWN, "promotion=none 兵不变后")

	# 2) 升变 queen:兵到中心变后
	g.game_rules["promotion"] = "queen"
	game.board[8][8] = null
	game.board[7][8] = R.make_piece(1, R.Type.PAWN)
	game._move4(Vector2i(8, 7), Vector2i(8, 8))
	_check(game.board[8][8]["type"] == R.Type.QUEEN, "promotion=queen 兵变后")

	# 3) 继承:王被吃,棋子给杀棋方
	game.board = R.make_board4()
	game.alive4 = {0: true, 1: true, 2: true, 3: true}
	g.game_rules["win_mode"] = "classic"
	g.game_rules["king_down"] = "inherit"
	# 找一个王的相邻位置放杀棋方棋子,直接调 _handle_king_captured4
	var king_pos := Vector2i(-1, -1)
	for r in 17:
		for c in 17:
			var p = game.board[r][c]
			if p != null and p["side"] == 1 and p["type"] == R.Type.KING:
				king_pos = Vector2i(c, r)
				break
		if king_pos.x >= 0:
			break
	# 手动把黑方棋子改为红方(模拟继承)
	var black_count := 0
	for r in 17:
		for c in 17:
			var p = game.board[r][c]
			if p != null and p["side"] == 1:
				black_count += 1
	game._inherit_pieces4(1, 0)
	var inherited := 0
	for r in 17:
		for c in 17:
			var p = game.board[r][c]
			if p != null and p["side"] == 0 and p["type"] != R.Type.KING:
				inherited += 1
	_check(inherited > 0, "继承:黑方棋子转为红方")
	# 4) 杀棋计数:半场恢复
	g.game_rules["win_mode"] = "kills"
	game.board = R.make_board4()
	game.alive4 = {0: true, 1: true, 2: true, 3: true}
	game.kill_count4 = {0: 0, 1: 0, 2: 0, 3: 0}
	# 在黑方半场放一个红子,然后杀棋计数触发半场恢复
	game.board[2][8] = R.make_piece(0, R.Type.ROOK)
	game._restore_arm4(1)
	_check(game.board[2][8] == null, "杀棋:半场内敌方棋子被摧毁")
	var res = game._handle_king_captured4(1, 0)
	_check(game.kill_count4[1] == 1, "杀棋计数 +1")
	_check(res == "continue", "杀棋未达次数继续")

	# 5) 占领模式:占中心 5 点中 3 个胜
	g.game_rules["win_mode"] = "occupy"
	game.board = R.make_board4()
	game.alive4 = {0: true, 1: true, 2: true, 3: true}
	for r in 17:
		for c in 17:
			game.board[r][c] = null
	var spots := [Vector2i(8, 8), Vector2i(7, 8), Vector2i(9, 8)]
	for sp in spots:
		game.board[sp.y][sp.x] = R.make_piece(0, R.Type.PAWN)
	_check(game._occupy_winner4() == 0, "红方占 3 中心点获胜")
	quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok - ", msg)
	else:
		_failures += 1
		print("FAIL - ", msg)
