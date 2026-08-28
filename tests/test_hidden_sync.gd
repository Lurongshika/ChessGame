# 隐者同步测试:godot --headless --path . --script res://tests/test_hidden_sync.gd
# 验证:客户端黑方释放隐者 → 主机执行 → 广播 → 客户端应用;
# 对方(红方)回合期间隐身标记保持,黑方下回合开始清除,两端始终一致
extends SceneTree

var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var R := preload("res://scripts/chess_rules.gd")
	# 44 技能池含逆位隐者(yinzhe2)
	var g = root.get_child(0)
	var A = load("res://scenes/game.tscn").instantiate()  # 主机(红方)
	var B = load("res://scenes/game.tscn").instantiate()  # 客户端(黑方)
	root.add_child(A)
	root.add_child(B)
	await process_frame
	A.net_role = "host"
	B.net_role = "client"
	A.perks_red = {}
	A.perks_black = {"yinzhe2": true}
	B.perks_red = {}
	B.perks_black = {"yinzhe2": true}
	A.turn = R.Side.BLACK
	B.turn = R.Side.BLACK
	A._setup_board()
	B._setup_board()

	# 找一个黑方棋子位置(黑方炮在 (1,2))
	var target := Vector2i(1, 2)
	_check(A.board[2][1] != null and A.board[2][1]["side"] == R.Side.BLACK, "目标位置是黑方棋子")

	# 模拟客户端黑方释放隐者(进阶:敌我所有子隐身三回合) → 主机执行(消耗本回合)
	A._apply_net_skill("yinzhe2", {})
	_check(not A.hidden_pieces.is_empty(), "主机:隐者标记已设置")
	_check(A.turn == R.Side.RED, "隐者:技能与落子二选一,使用后轮到红方")

	# 广播 → 客户端应用
	B._apply_state_data(A._state_to_data())
	_check(not B.hidden_pieces.is_empty(), "客户端:广播后隐者标记同步")
	_check(B.hidden_pieces.size() == A.hidden_pieces.size(), "两端隐者标记一致")

	# 倒计时结束(3 回合) → 清除
	A._clear_all_hidden()
	_check(A.hidden_pieces.is_empty(), "倒计时结束:隐身标记清除")
	B._apply_state_data(A._state_to_data())
	_check(B.hidden_pieces.is_empty(), "客户端:隐身标记同步清除")

	# --- 新规则:隐身的子不能吃子(但可移动到空格) ---
	A.board = []
	for rr in R.ROWS:
		var row := []
		for cc in R.COLS:
			row.append(null)
		A.board.append(row)
	A.board[0][0] = R.make_piece(R.Side.BLACK, R.Type.ROOK)
	A.board[3][0] = R.make_piece(R.Side.RED, R.Type.PAWN)  # 坐标 (0,3)
	A.turn = R.Side.BLACK
	A.hidden_pieces = {Vector2i(0, 0): R.Side.BLACK}
	_check(A._validate_move(Vector2i(0, 0), Vector2i(0, 3), "move", R.Side.BLACK) == false, "隐身的车不能吃子")
	_check(A._validate_move(Vector2i(0, 0), Vector2i(0, 2), "move", R.Side.BLACK) == true, "隐身的车可移动到空格")
	A.hidden_pieces = {}
	_check(A._validate_move(Vector2i(0, 0), Vector2i(0, 3), "move", R.Side.BLACK) == true, "非隐身车可正常吃子")

	# --- 新规则:恰好落到隐身子上则吃掉它 ---
	A.hidden_pieces = {Vector2i(0, 3): R.Side.RED}  # 红兵隐身(对方视角看不到)
	_check(A._validate_move(Vector2i(0, 0), Vector2i(0, 3), "move", R.Side.BLACK) == true, "非隐身车可以吃到隐身子")
	A._perform_move(Vector2i(0, 0), Vector2i(0, 3))
	_check(not A.hidden_pieces.has(Vector2i(0, 3)), "吃掉隐身子后标记清除")
	_check(A.board[3][0] != null and A.board[3][0]["side"] == R.Side.BLACK, "隐身子被吃后位置被黑车占据")

	# --- 新规则:对方视角完全看不到隐身子 ---
	A.hidden_pieces = {Vector2i(0, 0): R.Side.BLACK, Vector2i(8, 0): R.Side.RED}
	_check(A._is_visible_hidden(R.Side.BLACK) == false, "主机视角:黑方隐身子不可见")
	_check(A._is_visible_hidden(R.Side.RED) == true, "主机视角:红方隐身子可见")
	_check(B._is_visible_hidden(R.Side.RED) == false, "客户端视角:红方隐身子不可见")
	_check(B._is_visible_hidden(R.Side.BLACK) == true, "客户端视角:黑方隐身子可见")

	if _failures == 0:
		print("== HIDDEN SYNC OK ==")
	else:
		printerr("== %d HIDDEN SYNC CHECK(S) FAILED ==" % _failures)
	quit(0 if _failures == 0 else 1)


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  ok - ", name)
	else:
		_failures += 1
		printerr("FAIL - ", name)
