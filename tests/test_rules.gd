# 规则引擎自检:godot --headless --path . --script res://tests/test_rules.gd
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


func _empty_board() -> Array:
	var R := preload("res://scripts/chess_rules.gd")
	var b := R.make_board()
	for r in R.ROWS:
		for c in R.COLS:
			b[r][c] = null
	return b


func _test_all() -> void:
	var R := preload("res://scripts/chess_rules.gd")
	var Perks := preload("res://scripts/perks.gd")
	var AI := preload("res://scripts/ai.gd")
	var NO := {}

	print("-- 初始布局 --")
	var board := R.make_board()
	_check(R.piece_at(board, Vector2i(4, 9))["type"] == R.Type.KING and R.piece_at(board, Vector2i(4, 9))["side"] == R.Side.RED, "红帅在 (4,9)")
	_check(R.piece_at(board, Vector2i(4, 0))["type"] == R.Type.KING and R.piece_at(board, Vector2i(4, 0))["side"] == R.Side.BLACK, "黑将在 (4,0)")
	_check(R.piece_at(board, Vector2i(0, 0))["type"] == R.Type.ROOK, "黑车在 (0,0)")
	_check(R.piece_at(board, Vector2i(1, 2))["type"] == R.Type.CANNON, "黑炮在 (1,2)")
	_check(R.piece_at(board, Vector2i(1, 7))["type"] == R.Type.CANNON, "红炮在 (1,7)")
	_check(R.piece_at(board, Vector2i(4, 6))["type"] == R.Type.PAWN, "红兵在 (4,6)")
	_check(R.piece_at(board, Vector2i(2, 9))["type"] == R.Type.ELEPHANT, "红相在 (2,9)")

	print("-- 马 --")
	# 黑马 (1,0):周围 (0,0)车 (2,0)马 (1,1)空
	# 标准规则:马腿 = 日字长边方向第一步
	var horse := R.raw_moves(board, Vector2i(1, 0), NO, NO)
	_check(Vector2i(2, 2) in horse, "黑马可跳 (2,2)(腿 (1,1) 空)")
	_check(Vector2i(0, 2) in horse, "黑马可跳 (0,2)(腿 (1,1) 空)")
	_check(not (Vector2i(3, 1) in horse), "黑马被 (2,0) 马别腿不能跳 (3,1)")
	var horse_flying := R.raw_moves(board, Vector2i(1, 0), NO, {"zhengyi": true})
	_check(Vector2i(3, 1) in horse_flying, "飞马可跳过阻挡跳 (3,1)")
	_check(Vector2i(2, 2) in horse_flying, "飞马仍可跳 (2,2)")
	# 正义:马还能落到另一匹马所能落位的位置
	# 布局:黑马 (1,0) 与红马 (7,9);给 (1,0) 正义强化,另一马 (7,9) 的合法落位应可跳
	var b_j := R.make_board()
	# (7,9) 马(红)在标准开局,其落位含 (9,8)(5,8) 等;让 (1,0) 黑马(正义)能跳到这些位置
	var horse_jump := R.raw_moves(b_j, Vector2i(1, 0), NO, {"zhengyi": true})
	# 另一匹红马在 (7,9),其不被别腿落位如 (9,8)(5,8)(8,7)(6,7) 应可跳
	var other_horse_moves := R.raw_moves(b_j, Vector2i(7, 9), NO, {"zhengyi": true})
	for om in other_horse_moves:
		if not om in horse_jump:
			_check(false, "正义马未包含另一马落位 " + str(om))
			break
	_check(true, "正义马可跳至另一马所有落位")
	# 用户场景:标准开局红马 (7,9) 马二进三/进一可走,马二进四被相别住
	var b_init := R.make_board()
	var h_red := R.raw_moves(b_init, Vector2i(7, 9), NO, NO)
	_check(Vector2i(6, 7) in h_red, "马二进三可走 (6,7)")
	_check(Vector2i(8, 7) in h_red, "马二进一可走 (8,7)")
	_check(not (Vector2i(5, 8) in h_red), "马二进四被相别住 (5,8)")

	print("-- 车 --")
	var rook := R.raw_moves(board, Vector2i(0, 0), NO, NO)
	_check(Vector2i(0, 2) in rook, "车可走到 (0,2)")
	_check(not (Vector2i(0, 3) in rook), "车被炮阻挡不能到 (0,3)")
	_check(not (Vector2i(8, 0) in rook), "车不能吃己方车 (8,0)")
	var rook_diag := R.raw_moves(board, Vector2i(0, 0), NO, {"taiyang": true})
	_check(Vector2i(1, 1) in rook_diag, "车斜强化可走 (1,1)")

	print("-- 炮 --")
	var cannon := R.raw_moves(board, Vector2i(1, 2), NO, NO)
	_check(Vector2i(1, 6) in cannon, "炮可移动到 (1,6)")
	_check(not (Vector2i(1, 7) in cannon), "炮无架不能吃 (1,7)")
	var b2 := _empty_board()
	b2[2][1] = R.make_piece(R.Side.BLACK, R.Type.CANNON)
	b2[8][1] = R.make_piece(R.Side.RED, R.Type.ROOK)
	b2[9][1] = R.make_piece(R.Side.RED, R.Type.ROOK)
	var cannon2 := R.raw_moves(b2, Vector2i(1, 2), NO, NO)
	_check(Vector2i(1, 9) in cannon2, "炮隔一架可吃 (9,1)")
	_check(not (Vector2i(1, 8) in cannon2), "炮架本身不可吃")
	b2[6][1] = R.make_piece(R.Side.RED, R.Type.PAWN)
	var cannon_double := R.raw_moves(b2, Vector2i(1, 2), NO, {"_cannon_2": true})
	_check(Vector2i(1, 9) in cannon_double, "双炮架隔两子可吃 (1,9)")
	var cannon_normal_after := R.raw_moves(b2, Vector2i(1, 2), NO, NO)
	_check(not (Vector2i(1, 9) in cannon_normal_after), "普通炮隔两子不能吃 (1,9)")
	# 垫脚石:隔一个子仍可吃(不能只保留隔两个)
	b2[6][1] = null
	var cannon_double_one := R.raw_moves(b2, Vector2i(1, 2), NO, {"_cannon_2": true})
	_check(Vector2i(1, 9) in cannon_double_one, "双炮架隔一个子也可吃 (1,9)")

	print("-- 兵 --")
	var pawn := R.raw_moves(board, Vector2i(4, 6), NO, NO)
	_check(Vector2i(4, 5) in pawn, "红兵前进 (4,5)")
	_check(not (Vector2i(3, 6) in pawn), "红兵未过河不能横走")
	_check(not (Vector2i(4, 7) in pawn), "红兵不能后退")
	var b3 := _empty_board()
	b3[4][4] = R.make_piece(R.Side.RED, R.Type.PAWN)
	var pawn_crossed := R.raw_moves(b3, Vector2i(4, 4), NO, NO)
	_check(Vector2i(3, 4) in pawn_crossed, "过河红兵可横走 (3,4)")
	_check(Vector2i(4, 3) in pawn_crossed, "过河红兵可前进 (4,3)")
	# 精兵营:过河兵可斜向前吃子(仅吃子,不能斜走空位)
	b3[3][3] = R.make_piece(R.Side.BLACK, R.Type.PAWN)
	b3[3][5] = R.make_piece(R.Side.BLACK, R.Type.PAWN)
	var pawn_camp := R.raw_moves(b3, Vector2i(4, 4), {"ta": true}, NO)
	_check(Vector2i(3, 3) in pawn_camp, "塔过河兵斜吃 (3,3)")
	_check(Vector2i(5, 3) in pawn_camp, "塔过河兵斜吃 (5,3)")
	_check(not (Vector2i(3, 3) in pawn_crossed), "无塔不能斜吃")

	print("-- 象 --")
	var b4 := _empty_board()
	b4[9][2] = R.make_piece(R.Side.RED, R.Type.ELEPHANT)
	var ele := R.raw_moves(b4, Vector2i(2, 9), NO, NO)
	_check(Vector2i(0, 7) in ele and Vector2i(4, 7) in ele, "红相走田")
	b4[8][3] = R.make_piece(R.Side.RED, R.Type.PAWN)
	var ele2 := R.raw_moves(b4, Vector2i(2, 9), NO, NO)
	_check(not (Vector2i(4, 7) in ele2), "塞象眼不能跳 (4,7)")
	_check(Vector2i(0, 7) in ele2, "另一侧仍可跳 (0,7)")
	b4[5][2] = R.make_piece(R.Side.RED, R.Type.ELEPHANT)
	var ele3 := R.raw_moves(b4, Vector2i(2, 5), NO, NO)
	_check(not (Vector2i(4, 3) in ele3), "象不能过河 (4,3)")
	# 飞象:移动距离不受限制,可沿斜线直行
	var ele4 := R.raw_moves(b4, Vector2i(2, 5), {"yueliang": true}, NO)
	_check(Vector2i(4, 3) in ele4, "飞象可走到 (4,3)")
	_check(Vector2i(6, 1) in ele4, "飞象任意距离 (6,1)")
	_check(Vector2i(0, 7) in ele4, "飞象任意距离 (0,7)")
	b4[4][3] = R.make_piece(R.Side.BLACK, R.Type.PAWN)
	var ele5 := R.raw_moves(b4, Vector2i(2, 5), {"yueliang": true}, NO)
	_check(not (Vector2i(6, 1) in ele5), "飞象被路径阻挡 (6,1)")
	_check(Vector2i(3, 4) in ele5, "飞象可吃路径第一个子 (3,4)")

	print("-- 士/帅 --")
	var b5 := _empty_board()
	b5[9][3] = R.make_piece(R.Side.RED, R.Type.ADVISOR)
	var adv := R.raw_moves(b5, Vector2i(3, 9), NO, NO)
	_check(Vector2i(4, 8) in adv, "仕走斜 (4,8)")
	_check(not (Vector2i(2, 8) in adv), "仕被九宫限制 (2,8)")
	b5[9][4] = R.make_piece(R.Side.RED, R.Type.KING)
	var king := R.raw_moves(b5, Vector2i(4, 9), NO, NO)
	_check(Vector2i(4, 8) in king and Vector2i(5, 9) in king, "帅走一格")
	_check(not (Vector2i(4, 0) in king), "帅不能飞")

	print("-- 将军检测 --")
	var b6 := _empty_board()
	b6[0][4] = R.make_piece(R.Side.BLACK, R.Type.KING)
	b6[5][4] = R.make_piece(R.Side.RED, R.Type.ROOK)
	_check(R.is_in_check(b6, R.Side.BLACK, NO, NO), "车将军")
	b6[2][4] = R.make_piece(R.Side.BLACK, R.Type.PAWN)
	_check(not R.is_in_check(b6, R.Side.BLACK, NO, NO), "挡车解将")
	b6[2][4] = null
	b6[1][4] = R.make_piece(R.Side.RED, R.Type.PAWN)
	b6[2][4] = R.make_piece(R.Side.RED, R.Type.CANNON)
	_check(R.is_in_check(b6, R.Side.BLACK, NO, NO), "炮隔架将军")
	b6[1][4] = null
	_check(not R.is_in_check(b6, R.Side.BLACK, NO, NO), "炮无架不将军")
	var b7 := _empty_board()
	b7[0][4] = R.make_piece(R.Side.BLACK, R.Type.KING)
	b7[2][3] = R.make_piece(R.Side.RED, R.Type.HORSE)
	_check(R.is_in_check(b7, R.Side.BLACK, NO, NO), "马将军")
	b7[1][3] = R.make_piece(R.Side.BLACK, R.Type.PAWN)  # 马腿 (3,1)
	_check(not R.is_in_check(b7, R.Side.BLACK, NO, NO), "别马腿解将")

	print("-- 合法着法与吃王 --")
	var b8 := _empty_board()
	b8[9][4] = R.make_piece(R.Side.RED, R.Type.KING)
	b8[0][4] = R.make_piece(R.Side.BLACK, R.Type.ROOK)
	b8[4][4] = R.make_piece(R.Side.RED, R.Type.PAWN)
	var pawn_legal := R.legal_moves(b8, Vector2i(4, 4), NO, NO)
	_check(not (Vector2i(3, 4) in pawn_legal), "将军时兵不能横走离岗")
	_check(Vector2i(4, 3) in pawn_legal, "兵可前进继续挡线")
	var b9 := _empty_board()
	b9[0][4] = R.make_piece(R.Side.BLACK, R.Type.KING)
	b9[5][4] = R.make_piece(R.Side.RED, R.Type.ROOK)
	b9[9][4] = R.make_piece(R.Side.RED, R.Type.KING)
	var rook_legal := R.legal_moves(b9, Vector2i(4, 5), NO, NO)
	_check(Vector2i(4, 0) in rook_legal, "车可直接吃王")
	var res := R.apply_move(b9, Vector2i(4, 5), Vector2i(4, 0))
	_check(res["captured"]["type"] == R.Type.KING, "吃王捕获到王")
	_check(not R.has_legal_move(res["board"], R.Side.BLACK, NO, NO), "黑方被将死无合法着法")

	print("-- 抽卡 --")
	var taken := {}
	var rp := Perks.draw(3, taken)
	taken.merge(rp)
	var bp := Perks.draw(3, taken)
	_check(rp.size() == 3 and bp.size() == 3, "双方各抽 3 个")
	var overlap := false
	for id in rp:
		if bp.has(id):
			overlap = true
	_check(not overlap, "双方强化不重复")

	print("-- 边线过河兵 --")
	var b_edge: Array = []
	for r in R.ROWS:
		var er: Array = []
		for c in R.COLS:
			er.append(null)
		b_edge.append(er)
	b_edge[4][8] = R.make_piece(R.Side.RED, R.Type.PAWN)  # x=8 过河兵(最右列)
	var pm := R.legal_moves(b_edge, Vector2i(8, 4), NO, NO)
	var in_bounds := true
	for m in pm:
		if not R.in_board(m):
			in_bounds = false
	_check(in_bounds, "边线过河兵走法不出界")
	b_edge[4][0] = R.make_piece(R.Side.RED, R.Type.PAWN)  # x=0 过河兵(最左列)
	var pm2 := R.legal_moves(b_edge, Vector2i(0, 4), NO, NO)
	var in_bounds2 := true
	for m in pm2:
		if not R.in_board(m):
			in_bounds2 = false
	_check(in_bounds2, "左边线过河兵走法不出界")

	print("-- AI --")
	var mv := AI.choose_move(board, R.Side.RED, NO, NO)
	_check(not mv.is_empty(), "AI 有走法")
	if not mv.is_empty():
		var legal := R.legal_moves(board, mv["from"], NO, NO)
		_check(mv["to"] in legal, "AI 走法合法")
