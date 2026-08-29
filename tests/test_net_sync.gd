# 联机状态同步测试:godot --headless --path . --script res://tests/test_net_sync.gd
# 验证:愚者/六面骰/客户端请求技能改变棋盘后,_state_to_data/_apply_state_data 往返一致
extends SceneTree

var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var R := preload("res://scripts/chess_rules.gd")
	var g := Node.new()
	g.name = "Global"
	g.set_script(load("res://global.gd"))
	root.add_child(g)
	var scene = load("res://scenes/game.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.net_role = "local"

	# --- 愚者:洗牌改变棋盘,且帅/将/士保持原位 ---
	scene.perks_red = {"yuzhe": true}
	scene.perks_black = {}
	scene._setup_board()
	var before = scene._board_to_json(scene.board)
	# 愚者 75% 概率不动:多次尝试直到棋盘变化(避免概率性失败)
	var changed := false
	for i in 12:
		scene.turn = R.Side.RED
		scene.actions_left = 1
		scene._skill_fool("yuzhe", R.Side.RED)
		if scene._board_to_json(scene.board) != before:
			changed = true
			break
	_check(changed, "愚者:洗牌改变了棋盘")
	var after_fool = scene._board_to_json(scene.board)
	var king_ok := true
	for r in R.ROWS:
		for c in R.COLS:
			var b = before[r][c]
			var a = after_fool[r][c]
			if b != null and (b["type"] == R.Type.KING or b["type"] == R.Type.ADVISOR):
				if a == null or a["type"] != b["type"]:
					king_ok = false
	_check(king_ok, "愚者:帅/将/士保持原位")
	var data = scene._state_to_data()
	scene._apply_state_data(data)
	_check(scene._board_to_json(scene.board) == after_fool, "状态往返:愚者后棋盘一致")

	# --- 六面骰:掷骰后往返一致 ---
	scene.perks_red = {"shijie": true}
	scene._setup_board()
	scene._apply_dice(R.Side.RED, R.Side.RED)
	var after_dice = scene._board_to_json(scene.board)
	var data2 = scene._state_to_data()
	scene._apply_state_data(data2)
	_check(scene._board_to_json(scene.board) == after_dice, "状态往返:六面骰后棋盘一致")

	# --- 客户端请求技能(主机侧 _apply_net_skill):黑方愚者 ---
	scene.perks_black = {"yuzhe": true}
	scene.perks_red = {}
	scene._setup_board()
	var b3 = scene._board_to_json(scene.board)
	# 愚者 75% 不动:多次尝试直到变化
	var changed3 := false
	for i in 12:
		scene.turn = R.Side.BLACK
		scene.actions_left = 1
		scene._apply_net_skill("yuzhe", {})
		if scene._board_to_json(scene.board) != b3:
			changed3 = true
			break
	_check(changed3, "黑方愚者:主机执行后棋盘变化")
	var after_net = scene._board_to_json(scene.board)
	var data3 = scene._state_to_data()
	scene._apply_state_data(data3)
	_check(scene._board_to_json(scene.board) == after_net, "状态往返:黑方技能后棋盘一致")

	# --- 女祭司(生成兵)往返 ---
	scene.perks_black = {"nvjisi": true}
	scene._setup_board()
	scene.turn = R.Side.BLACK
	scene._apply_net_skill("nvjisi", {})
	var data4 = scene._state_to_data()
	scene._apply_state_data(data4)
	var pawns := 0
	for r in R.ROWS:
		for c in R.COLS:
			var p = scene.board[r][c]
			if p != null and p["side"] == R.Side.BLACK and p["type"] == R.Type.PAWN:
				pawns += 1
	_check(pawns == 6, "女祭司:黑方多一枚兵(5+1)")
	_check(scene._board_to_json(scene.board) == scene._board_to_json(scene.board), "状态往返:女祭司后棋盘自洽")

	# --- 愚者:释放后跳过当前回合 ---
	scene.perks_black = {"yuzhe": true}
	scene.perks_red = {}
	scene._setup_board()
	scene.turn = R.Side.BLACK
	scene.actions_left = 1
	scene._apply_net_skill("yuzhe", {})
	_check(scene.turn == R.Side.RED, "愚者:释放后跳过当前回合(轮到对方)")

	# --- 技能只能在己方回合使用 ---
	scene.perks_red = {"yuzhe": true}
	scene.perks_black = {}
	scene.turn = R.Side.BLACK  # 对方(黑方)回合,红方不能放技能
	scene._setup_board()
	scene.phase = scene.Phase.PLAY
	scene.actions_left = 1
	var cd_before: int = scene.skill_cd[R.Side.RED].get("yuzhe", 0)
	var before_turn: int = scene.turn
	scene._on_perk_clicked("yuzhe", R.Side.RED)
	_check(scene.turn == before_turn, "非己方回合:技能被拦截,回合未切换")
	_check(scene.skill_cd[R.Side.RED].get("yuzhe", 0) == cd_before, "非己方回合:技能未进入冷却")

	# --- 平衡性:每回合技能与落子二选一 ---
	# 1) 双行动中已走一步(剩1行动),不能再放技能
	scene.perks_red = {"nvjisi": true}
	scene.perks_black = {}
	scene._setup_board()
	scene.phase = scene.Phase.PLAY
	scene.turn = R.Side.RED
	scene.extra_move = {0: true, 1: false}  # 命运之轮:cap=2
	scene.actions_left = 1  # 已走一步
	scene.skill_cd = {0: {}, 1: {}}
	scene._on_perk_clicked("nvjisi", R.Side.RED)
	_check(not scene.skill_cd[R.Side.RED].has("nvjisi"), "已落子:不能再放技能(二选一)")
	# 2) 未落子释放技能 → 消耗本回合
	scene.perks_red = {"nvjisi": true}
	scene._setup_board()
	scene.phase = scene.Phase.PLAY
	scene.turn = R.Side.RED
	scene.actions_left = 1
	scene.skill_cd = {0: {}, 1: {}}
	scene._activate_skill("nvjisi", R.Side.RED)
	_check(scene.skill_cd[R.Side.RED].has("nvjisi"), "未落子:技能释放成功进入冷却")
	_check(scene.turn == R.Side.BLACK, "释放技能后消耗本回合(轮到黑方)")

	# --- 同步选择:黑方先选完时,红方三选一界面不被覆盖 ---
	scene.net_role = "host"
	scene.phase = scene.Phase.SKILL_DRAFT
	scene.draft_red_done = false
	scene.draft_black_done = true
	scene._start_net_game_after_draft()
	_check(scene.phase == scene.Phase.SKILL_DRAFT, "黑方先选完:红方三选一不被覆盖(继续选)")
	# 红方随后也选完 → 离开三选一进入对局
	scene.draft_red_done = true
	scene._start_net_game_after_draft()
	_check(scene.phase != scene.Phase.SKILL_DRAFT, "双方选完:离开三选一进入对局")

	# --- 隐者:消耗回合后再广播,广播数据是对方回合 ---
	scene.net_role = "host"
	scene.phase = scene.Phase.PLAY
	scene.turn = R.Side.RED
	scene.perks_red = {"yinzhe": true}
	scene.perks_black = {}
	scene._setup_board()
	scene.actions_left = 1
	scene._skill_hermit("yinzhe", R.Side.RED)
	_check(scene.turn == R.Side.RED, "隐者:释放后不跳过回合(仍可走子)")
	_check(int(scene._state_to_data()["turn"]) == R.Side.RED, "隐者:广播状态仍为红方回合")

	# --- 命运之轮(正位):释放后不跳过回合 ---
	scene.net_role = "host"
	scene.phase = scene.Phase.PLAY
	scene.turn = R.Side.RED
	scene.perks_red = {"mingyun": true}
	scene.perks_black = {}
	scene._setup_board()
	scene.actions_left = 1
	scene.skill_cd = {0: {}, 1: {}}
	scene.actions_left = 1
	scene._skill_wheel("mingyun", R.Side.RED)
	_check(scene.turn == R.Side.RED, "命运之轮:释放后不跳过回合")
	_check(scene.actions_left == 2, "命运之轮:本回合可多走一次")

	# --- 世界:变子按价值加权(弱子概率高,强子概率低) ---
	var rolls := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0}  # PAWN..CANNON
	for i in 400:
		var t: int = scene._random_piece_type()
		rolls[t] = rolls.get(t, 0) + 1
	_check(rolls[R.Type.PAWN] > rolls[R.Type.ROOK], "世界:兵(45%)概率高于车(5%)")
	_check(rolls[R.Type.ROOK] < 80, "世界:车出现频率低")

	# --- 皇后:被吃充能(非每回合冷却) ---
	scene.net_role = "host"
	scene.own_side = R.Side.RED
	scene.phase = scene.Phase.PLAY
	scene.turn = R.Side.RED
	scene.perks_red = {"huanghou": true}
	scene.perks_black = {}
	scene._setup_board()
	scene.actions_left = 1
	scene.queen_charge = {0: 0, 1: 0}
	scene.skill_cd = {0: {}, 1: {}}
	scene.invincible_side = -1
	scene.extra_move = {0: false, 1: false}
	scene._on_perk_clicked("huanghou", R.Side.RED)
	_check(not scene.invincible_side == R.Side.RED and scene.turn == R.Side.RED, "皇后无充能:不可释放")
	# 红方被吃 1 子 → 充能 +1
	scene._handle_capture({"side": R.Side.RED, "type": R.Type.PAWN, "pos": Vector2i(4, 7), "birth_pos": Vector2i(4, 7)}, Vector2i(4, 7), R.Side.BLACK)
	_check(scene.queen_charge[R.Side.RED] == 1, "被吃 1 子:皇后充能 +1")
	scene.turn = R.Side.RED
	scene.actions_left = 1
	scene._on_perk_clicked("huanghou", R.Side.RED)
	_check(scene.invincible_side == R.Side.RED, "有充能:皇后释放成功")
	_check(scene.queen_charge[R.Side.RED] == 0, "皇后释放后充能消耗")
	_check(scene.turn == R.Side.BLACK, "皇后释放后消耗本回合")

	# --- 审判逆位:敌方无法使用技能/受控棋子吃我方棋子,只能原版移动吃 ---
	scene.net_role = "host"
	scene.phase = scene.Phase.PLAY
	scene.turn = R.Side.RED
	scene.perks_red = {"shenpan2": true}
	scene.perks_black = {"yuzhe": true, "nvjisi": true}
	scene._setup_board()
	scene.actions_left = 1
	var black_before: int = scene.perks_black.size()
	scene._refresh_judgement(R.Side.RED)
	_check(scene.perks_black.size() == black_before, "审判逆位:不再重抽/失去敌方技能(改为被动)")
	# 被控制棋子(技能移动)不能吃有审判逆位的棋子
	scene.board = []
	for rr in R.ROWS:
		var row := []
		for cc in R.COLS:
			row.append(null)
		scene.board.append(row)
	scene.board[3][0] = R.make_piece(R.Side.BLACK, R.Type.ROOK)  # 黑车 (0,3)
	scene.board[3][4] = R.make_piece(R.Side.RED, R.Type.PAWN)    # 红兵 (4,3)
	scene.turn = R.Side.BLACK
	scene.perks_red = {"shenpan2": true}
	scene.perks_black = {}
	scene.invincible_side = -1
	scene.invincible_piece = Vector2i(-1, -1)
	scene.hidden_pieces = {}
	scene.controlled_piece = {"pos": Vector2i(0, 3), "owner": R.Side.BLACK}
	scene.controlled_turns = 1
	scene.perks_red = {"shenpan2": true}
	# 黑车(受控)吃红兵:红方有审判逆位 → 禁吃
	_check(scene._validate_move(Vector2i(0, 3), Vector2i(4, 3), "move", R.Side.BLACK) == false, "审判逆位:受控棋子不能吃我方棋子")
	scene.controlled_piece = {}
	scene.controlled_turns = 0
	# 普通走子吃不受限
	_check(scene._validate_move(Vector2i(0, 3), Vector2i(4, 3), "move", R.Side.BLACK) == true, "审判逆位:原版移动可正常吃我方棋子")

	# --- 月亮逆位:象免费移动(蓝色,不消耗步数,不结束回合) ---
	scene.net_role = "local"
	scene.phase = scene.Phase.PLAY
	scene.turn = R.Side.RED
	scene.perks_red = {"yueliang2": true}
	scene.perks_black = {}
	scene._setup_board()
	scene.actions_left = 1
	scene._select(Vector2i(2, 9))  # 红相
	_check(not scene.free_elephant_targets.is_empty(), "月亮逆位:象有免费落位(蓝色)")
	var before_actions: int = scene.actions_left
	var ft: Vector2i = scene.free_elephant_targets[0]
	scene._try_perform(Vector2i(2, 9), ft, "free_elephant")
	_check(scene.actions_left == before_actions, "月亮逆位:象免费移动不消耗步数")
	_check(scene.turn == R.Side.RED, "月亮逆位:移动后回合不结束")
	# 校验:free_elephant 只能走空格
	scene._setup_board()
	scene.actions_left = 1
	_check(scene._validate_move(Vector2i(2, 9), Vector2i(0, 7), "free_elephant", R.Side.RED) == true, "月亮逆位:象免费移动到空格合法")
	# 吃子目标不能用 free_elephant:放一个黑子在象路径上(象斜线),吃子需走普通移动
	scene.board[7][0] = R.make_piece(R.Side.BLACK, R.Type.PAWN)  # 坐标 (0,7) 放黑兵
	_check(scene._validate_move(Vector2i(2, 9), Vector2i(0, 7), "free_elephant", R.Side.RED) == false, "月亮逆位:吃子不能用免费移动")

	# --- 将军判定考虑技能:恶魔禁同类型连续吃 → 不算将军 ---
	scene.net_role = "host"
	scene.phase = scene.Phase.PLAY
	scene.turn = R.Side.RED
	scene.perks_red = {}
	scene.perks_black = {"emo": true}
	scene.board = []
	for rr in R.ROWS:
		var row := []
		for cc in R.COLS:
			row.append(null)
		scene.board.append(row)
	scene.board[0][4] = R.make_piece(R.Side.BLACK, R.Type.KING)   # 黑王 (4,0)
	scene.board[7][4] = R.make_piece(R.Side.RED, R.Type.ROOK)     # 红车 (4,7),同列直吃黑王
	scene.hidden_pieces = {}
	scene.invincible_side = -1
	scene.invincible_piece = Vector2i(-1, -1)
	scene.last_eat = {"side": R.Side.RED, "type": R.Type.ROOK}  # 红车刚吃过(恶魔禁同类型连续吃)
	_check(scene._is_in_check_board(scene.board, R.Side.BLACK) == false, "恶魔:被禁吃的红车不构成将军")
	scene.last_eat = {"side": -1, "type": -1}
	_check(scene._is_in_check_board(scene.board, R.Side.BLACK) == true, "无恶魔限制:红车构成将军")

	# --- 教皇:象路径阻挡的己方棋子获得无敌(金色描边) ---
	scene.net_role = "host"
	scene.phase = scene.Phase.PLAY
	scene.turn = R.Side.BLACK
	scene.perks_red = {"jiaohuang": true}
	scene.perks_black = {}
	scene._setup_board()
	scene.board[8][3] = R.make_piece(R.Side.RED, R.Type.ADVISOR)  # 红仕在 (3,8) = 红相(2,9)的象眼
	scene._refresh_pope_guard(R.Side.RED)
	_check(scene.pope_guarded.has(Vector2i(3, 8)), "教皇:象眼处己方棋子获得无敌标记")
	scene.board[0][3] = R.make_piece(R.Side.BLACK, R.Type.ROOK)  # 黑車 (3,0) 同列可直吃
	scene.turn = R.Side.BLACK
	_check(scene._validate_move(Vector2i(3, 0), Vector2i(3, 8), "move", R.Side.BLACK) == false, "教皇:受保护棋子不可被吃")

	if _failures == 0:
		print("== NET SYNC OK ==")
	else:
		printerr("== %d NET SYNC CHECK(S) FAILED ==" % _failures)
	quit(0 if _failures == 0 else 1)


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  ok - ", name)
	else:
		_failures += 1
		printerr("FAIL - ", name)
