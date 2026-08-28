# 兵到中心变"后" + 后八向不限距离移动测试
extends SceneTree

var _failures := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	var R := preload("res://scripts/chess_rules.gd")
	# 1) 后的走法:八向不限距离
	var b: Array = R.make_board4()
	# 清空中心附近,放一个后
	for r in 17:
		for c in 17:
			b[r][c] = null
	b[8][8] = R.make_piece(1, R.Type.QUEEN)
	# 中心放一个敌方子在(8,0)远处,验证可到达
	b[0][8] = R.make_piece(0, R.Type.PAWN)
	var moves: Array = R.raw_moves4(b, Vector2i(8, 8), [{}, {}, {}, {}])
	_check(Vector2i(8, 0) in moves, "后八向直达(8,0)")
	_check(Vector2i(0, 8) in moves, "后八向直达(0,8)")
	_check(Vector2i(0, 0) in moves, "后八向斜线(0,0)")
	_check(Vector2i(16, 16) in moves, "后八向斜线(16,16)")
	_check(Vector2i(8, 1) in moves, "后直线空位(8,1)可达")
	_check(not Vector2i(8, -1) in moves, "后不可越界")
	# 2) 兵到中心变后(直接用 game 的 board,避免结构问题)
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.four_mode = true
	game.board = R.make_board4()
	game.turn4 = 0
	game.alive4 = {0: true, 1: true, 2: true, 3: true}
	game.perks4 = {0: {}, 1: {}, 2: {}, 3: {}}
	game._draft_selected4 = []
	game.phase = game.Phase.PLAY
	# 清空中心,放黑兵(8,7)和中心目标
	for r in 17:
		for c in 17:
			game.board[r][c] = null
	game.board[7][8] = R.make_piece(1, R.Type.PAWN)
	game.board[8][8] = null
	game._select4(Vector2i(8, 7))
	game._move4(Vector2i(8, 7), Vector2i(8, 8))
	_check(game.board[8][8]["type"] == R.Type.QUEEN, "黑兵到中心变后")
	# 3) 后的八向走法在 game.board 上验证
	var moves2: Array = R.raw_moves4(game.board, Vector2i(8, 8), [{}, {}, {}, {}])
	_check(Vector2i(8, 0) in moves2, "后八向直达(8,0)")
	quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok - ", msg)
	else:
		_failures += 1
		print("FAIL - ", msg)
