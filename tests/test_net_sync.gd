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
	# --- 命运之轮(逆位):随机两子协同,也不跳过本回合 ---
	scene.net_role = "host"
	scene.phase = scene.Phase.PLAY
	scene.turn = R.Side.RED
	scene.perks_red = {"mingyun2": true}
	scene.perks_black = {}
	scene._setup_board()
	scene.actions_left = 1
	scene.skill_cd = {0: {}, 1: {}}
	scene._skill_wheel("mingyun2", R.Side.RED)
	_check(scene.turn == R.Side.RED, "命运之轮逆位:释放后不跳过回合")
	_check(scene.sync_pieces.size() == 2, "命运之轮逆位:两子进入协同状态")
	_check(scene.actions_left == 1, "命运之轮逆位:不额外增加行动(仅协同)")
	# 协同棋子移动后,协同位置跟随棋子(描边不再停留原地)
	var sp0: Vector2i = scene.sync_pieces[0]
	var sp_mv: Vector2i = sp0
	# 找该协同子一个合法移动(空位)
	var sp_moves: Array = R.legal_moves(scene.board, sp0, scene.perks_red, scene.perks_black)
	var sp_target := Vector2i(-1, -1)
	for mm in sp_moves:
		if scene.board[mm.y][mm.x] == null:
			sp_target = mm
			break
	if sp_target.x >= 0:
		var actions_before_sync: int = scene.actions_left
		scene._perform_move(sp0, sp_target)
		_check(not sp0 in scene.sync_pieces, "协同:原位置描边移除")
		_check(sp_target in scene.sync_pieces, "协同:描边跟随到新位置")
		_check(scene.actions_left == actions_before_sync, "协同:移动不消耗行动")

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

	# --- 审判逆位:敌方吃我方棋子时,纯规则(无技能)吃不到则禁止 ---
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
	# 黑车纯规则可直线吃红兵 → 允许
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
	_check(scene._validate_move(Vector2i(0, 3), Vector2i(4, 3), "move", R.Side.BLACK) == true, "审判逆位:纯规则可吃(原版移动)允许")
	# 黑马在 (4,2),红兵在 (4,3) 正前方:马需斜跳吃(纯规则吃不到正前方) → 但用塔逆位八向技能可吃 → 禁止
	scene.board[2][4] = R.make_piece(R.Side.BLACK, R.Type.HORSE)  # 黑马 (4,2)
	scene.board[3][4] = R.make_piece(R.Side.RED, R.Type.PAWN)     # 红兵 (4,3) 马正前方
	scene.perks_black = {"ta2": true}  # 塔逆位:八向移动一格(靠技能才能吃正前方)
	_check(scene._validate_move(Vector2i(4, 2), Vector2i(4, 3), "move", R.Side.BLACK) == false, "审判逆位:靠技能增强才能吃 → 禁止")
	scene.perks_black = {}

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

	# --- 对局记录同步:敌我双方技能都随状态广播 ---
	scene.net_role = "host"
	scene.phase = scene.Phase.PLAY
	scene.perks_red = {"yuzhe": true}
	scene.perks_black = {"nvjisi": true}
	scene._setup_board()
	scene.turn = R.Side.RED
	scene.actions_left = 1
	scene.move_history = []
	scene._record_skill(R.Side.RED, "yuzhe")     # 主机(红方)技能
	scene._record_skill(R.Side.BLACK, "nvjisi")  # 客户端(黑方)技能
	var hist_kinds: Array = []
	for m in scene.move_history:
		hist_kinds.append(str(m["side"]) + ":" + str(m["kind"]))
	_check(hist_kinds.has("0:skill") and hist_kinds.has("1:skill"), "双人:双方技能都进入 move_history")
	var data_sync = scene._state_to_data()
	_check(data_sync.has("move_history"), "双人:状态广播包含 move_history")
	scene.move_history = []
	scene._apply_state_data(data_sync)
	var restored: Array = []
	for m in scene.move_history:
		restored.append(str(m["side"]) + ":" + str(m["kind"]))
	_check(restored.has("0:skill") and restored.has("1:skill"), "双人:客户端收到广播后含双方技能记录")
	# 四人:record4_history 随状态广播
	scene._record4_history = []
	scene._record_skill4(0, "nvjisi")
	scene._record_skill4(2, "yuzhe")
	var data4_sync = scene._state_to_data4()
	_check(data4_sync.has("record4_history") and data4_sync["record4_history"].size() == 2, "四人:状态广播包含 record4_history")
	scene._record4_history = []
	scene._apply_state_data4(data4_sync)
	_check(scene._record4_history.size() == 2, "四人:客户端收到广播后含双方技能记录")

	# --- 逆位魔术师:敌方将/帅不可被交换 ---
	scene.net_role = "host"
	scene.phase = scene.Phase.PLAY
	scene.perks_red = {}
	scene.perks_black = {"moshushi2": true}
	scene._setup_board()
	# 双人:host 权威执行 _apply_net_skill(moshushi2) 校验 —— 红帅(4,9)不可交换
	scene.turn = R.Side.BLACK
	scene.actions_left = 1
	var king_pos := Vector2i(4, 9)   # 红帅(黑方逆位魔术师的敌方将)
	var pawn_pos := Vector2i(0, 6)   # 红兵(敌方普通子)
	var b_swap = scene._board_to_json(scene.board)
	scene._apply_net_skill("moshushi2", {"a": [king_pos.x, king_pos.y], "b": [pawn_pos.x, pawn_pos.y]})
	_check(scene._board_to_json(scene.board) == b_swap, "双人:逆位魔术师 host 校验拒绝交换敌方将/帅")
	# 双人:本地选目标 _handle_swap_target 拒绝将/帅
	scene.net_role = "local"
	scene.perks_black = {"moshushi2": true}
	scene.turn = R.Side.BLACK
	scene.actions_left = 1
	scene.targeting = {"perk": "moshushi2", "side": R.Side.BLACK, "stage": 1, "data": {}}
	scene._handle_swap_target(king_pos, R.Side.BLACK, "moshushi2")
	_check(not scene.targeting.get("data", {}).has("a"), "双人:本地选目标拒绝敌方将/帅(不进入第二步)")
	# 双人:非将/帅的敌方棋子可正常选中
	scene.targeting = {"perk": "moshushi2", "side": R.Side.BLACK, "stage": 1, "data": {}}
	scene._handle_swap_target(pawn_pos, R.Side.BLACK, "moshushi2")
	_check(scene.targeting.get("data", {}).get("a", Vector2i(-1, -1)) == pawn_pos, "双人:敌方非将棋子可正常选中")
	# 四人:选其他方将/帅被拒绝
	scene._record4_history = []
	scene.four_mode = true
	scene.net_role = "local"
	scene.actions_left4 = 1
	scene.turn4 = 1  # 黑方回合
	scene.board = R.make_board4()
	var k4 := Vector2i(-1, -1)
	for rr in 17:
		for cc in 17:
			var q = scene.board[rr][cc]
			if q != null and q["side"] == 1 and q["type"] == R.Type.KING:
				k4 = Vector2i(cc, rr)
				break
	_check(k4.x >= 0, "四人:找到黑将位置")
	scene.targeting4 = {"perk": "moshushi2", "side": 0, "stage": 1, "data": {}}
	scene._handle_swap_target4(k4, 0, "moshushi2")
	_check(not scene.targeting4.get("data", {}).has("a"), "四人:逆位魔术师拒绝交换其他方将/帅")
	scene.four_mode = false

	# --- 目标型技能完整列表:正逆位都本地选目标(不显示"等待对方确认") ---
	# 与 _activate_skill/_start_targeting 的 match 分支一致:魔术师/皇帝/战车(含逆位)必须为 true
	var targeting_expected := {
		"moshushi": true, "moshushi2": true,
		"huangdi": true, "huangdi2": true,
		"siwang": true,
		"zhanche": false, "zhanche2": false,  # 战车已改为被动(整局走法强化)
		"diaodiao": true,
		# 非目标型(直接发请求,host 端执行):隐者/倒吊人逆位/女祭司/愚者等
		"yinzhe": false, "yinzhe2": false,
		"diaodiao2": false,
		"nvjisi": false, "yuzhe": false,
	}
	var targeting_ok := true
	for pid in targeting_expected:
		if scene._is_targeting_skill(pid) != targeting_expected[pid]:
			targeting_ok = false
			printerr("FAIL - 目标型列表 %s 期望 %s 实际 %s" % [pid, targeting_expected[pid], scene._is_targeting_skill(pid)])
	_check(targeting_ok, "目标型技能列表完整(正逆位都本地选目标,非目标型直接请求)")

	# --- 战车(被动·整局):与车相邻的棋子可落至车的可落位;选中车时可落至相邻子可落位 ---
	scene.net_role = "local"
	scene.phase = scene.Phase.PLAY
	scene.turn = R.Side.RED
	scene.actions_left = 1
	scene.perks_red = {"zhanche": true}
	scene.perks_black = {}
	scene.board = []
	for rr in R.ROWS:
		var row := []
		for cc in R.COLS:
			row.append(null)
		scene.board.append(row)
	# 红车 (4,7),红兵 (5,7) 横向相邻:兵的可落位应包含车的可落位(车正上方无阻挡 → (4,0))
	scene.board[7][4] = R.make_piece(R.Side.RED, R.Type.ROOK)
	scene.board[7][5] = R.make_piece(R.Side.RED, R.Type.PAWN)
	scene.board[0][4] = R.make_piece(R.Side.BLACK, R.Type.KING)
	scene.selected4 = Vector2i(-1, -1)
	scene.moves_cache.clear()
	scene._select(Vector2i(5, 7))
	var pawn_has_rook_landing := false
	for m in scene.moves_cache:
		if m.x == 4 and m.y == 0:  # 车的可落位:吃黑将 (4,0)
			pawn_has_rook_landing = true
	_check(pawn_has_rook_landing, "战车正位:与车相邻的兵可落至车的可落位(远距离)")
	# host 校验放行:兵 (5,7) → (4,0) 车落位
	scene.net_role = "host"
	scene.turn = R.Side.RED
	_check(scene._validate_move(Vector2i(5, 7), Vector2i(4, 0), "move", R.Side.RED) == true, "战车正位:host 校验放行战车落位移动")
	# 战车逆位:选中车时,相邻子可落位并入车的落位
	scene.perks_red = {"zhanche2": true}
	scene.net_role = "local"
	scene.moves_cache.clear()
	scene._select(Vector2i(4, 7))  # 选中车
	# 兵的合法落位:前进一格 (5,6) = 车的强化落位之一
	var rook_has_any_boost := false
	for m in scene.moves_cache:
		if m == Vector2i(5, 6):  # 相邻兵前进一格 = 车的强化落位
			rook_has_any_boost = true
	_check(rook_has_any_boost, "战车逆位:选中车时,相邻子可落位并入车的落位")
	# 四人:战车正位强化落位
	scene.four_mode = true
	scene.net_role = "local"
	scene.board = []
	for rr in 17:
		var row4 := []
		for cc in 17:
			row4.append(null)
		scene.board.append(row4)
	scene.board[14][8] = R.make_piece(R.Side.RED, R.Type.ROOK)  # 红车 (8,14)
	scene.board[14][9] = R.make_piece(R.Side.RED, R.Type.PAWN)  # 红兵 (9,14) 与车横向相邻
	scene.board[0][8] = R.make_piece(R.Side.BLACK, R.Type.KING)  # 黑将 (8,0) 车正上方无阻挡
	scene.perks4 = {0: {"zhanche": true}, 1: {}, 2: {}, 3: {}}
	scene.turn4 = 2  # 红方回合
	scene.moves4.clear()
	scene._select4(Vector2i(9, 14))
	var four_has_boost := false
	for m in scene.moves4:
		if m == Vector2i(8, 0):  # 车的可落位(吃到黑将)
			four_has_boost = true
	_check(four_has_boost, "四人战车正位:相邻兵可落至车的可落位")
	scene.four_mode = false

	# --- 星星逆位:使用后不跳过回合,获得蓄势 ---
	scene.net_role = "local"
	scene.phase = scene.Phase.PLAY
	scene.turn = R.Side.RED
	scene.actions_left = 1
	scene.perks_red = {"xingxing2": true}
	scene.perks_black = {}
	scene._setup_board()
	scene.star2_charge = {0: 0, 1: 0}
	scene.skill_cd = {0: {}, 1: {}}
	scene._activate_skill("xingxing2", R.Side.RED)
	_check(scene.turn == R.Side.RED, "星星逆位:使用后不跳过本回合")
	_check(scene.star2_charge[R.Side.RED] == 2, "星星逆位:获得 2 蓄势")
	# 星星逆位:兵可免费移动一格(蓝色落位)
	scene._select(Vector2i(0, 6))  # 红兵
	var star_free_ok := false
	for m in scene.free_retreat_targets:
		if m == Vector2i(0, 5):
			star_free_ok = true
	_check(star_free_ok, "星星逆位:兵有免费移兵落位")
	var actions_before: int = scene.actions_left
	scene._perform_free_retreat(Vector2i(0, 6), Vector2i(0, 5))
	_check(scene.star2_charge[R.Side.RED] == 1, "星星逆位:免费移兵消耗 1 蓄势")
	_check(scene.actions_left == actions_before, "星星逆位:免费移兵不消耗行动")
	# 星星正位:点击免费落点优先走免费移动(不消耗行动),而非普通移动
	scene._setup_board()
	scene.perks_red = {"xingxing": true}
	scene.free_retreat_used = false
	scene.turn = R.Side.RED
	scene.actions_left = 1
	scene._select(Vector2i(0, 6))  # 红兵
	# (0,5) 前进一格同时是普通走法与星星免费落点
	var act_before2: int = scene.actions_left
	scene._handle_click(Vector2i(0, 5))
	_check(scene.actions_left == act_before2, "星星正位:点击免费落点走免费移动(不消耗行动)")
	_check(scene.free_retreat_used, "星星正位:免费移动标记已用(每回合一次)")

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
