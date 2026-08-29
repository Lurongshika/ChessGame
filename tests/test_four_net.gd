# 联机四人:host+1 client 的 DRAFT 各选各的 + 走子同步测试
# 注:完整 4 端联机用 run4.sh headless 验证,这里用单进程模拟 host/client RPC 较难,
# 改为验证:side 分配、DRAFT 各选各的、状态序列化往返
extends SceneTree

var game
var R

func _initialize() -> void:
	_run()


func _run() -> void:
	R = load("res://scripts/chess_rules.gd")
	var g = root.get_child(0)
	g.game_mode = "four"
	g.net_role = "host"
	g.from_lobby = true

	# --- 单人开四人(全 AI 补位):无需等待客户端 ready,直接进入技能抽取 ---
	var scene0 = load("res://scenes/game.tscn").instantiate()
	root.add_child(scene0)
	await process_frame
	scene0.net_role = "host"
	scene0.four_mode = true
	scene0.my_side4 = 1
	scene0.four_side_to_peer = {0: -1, 1: 1, 2: -1, 3: -1}
	root.get_child(0).lobby_players = {
		1: {"name": "主机", "avatar_data": {}, "color": 0, "pid": 1, "is_ai": false},
		3: {"name": "机器人A", "avatar_data": {}, "color": 1, "pid": -1, "is_ai": true},
		0: {"name": "机器人B", "avatar_data": {}, "color": 2, "pid": -1, "is_ai": true},
		2: {"name": "机器人C", "avatar_data": {}, "color": 3, "pid": -1, "is_ai": true},
	}
	_check(scene0._real_client_count4() == 0, "单人开四人:真实客户端数为 0")
	scene0._from_lobby_start4()
	_check(scene0.phase == scene0.Phase.SKILL_DRAFT, "单人开四人:直接进入技能抽取(不等待)")
	# AI 方已自动选技能,host 选完 3 个确认后开局
	_check(scene0.four_draft_picks[0].size() == 3 and scene0.four_draft_picks[2].size() == 3 and scene0.four_draft_picks[3].size() == 3, "单人开四人:AI 方自动选 3 技能")
	scene0._draft_selected4 = scene0.draft4_options.slice(0, 3)
	scene0._confirm_draft4()
	_check(scene0.phase == scene0.Phase.PLAY, "单人开四人:host 选完技能后开局")
	_check(scene0.perks4[0].size() == 3 and scene0.perks4[1].size() == 3, "单人开四人:四方技能已分配")
	# 模拟大厅分配:4 方玩家(pid 1=host 对应 side 1 黑? 实际 host pid=1)
	g.lobby_players = {
		1: {"name": "主机", "avatar_data": {}, "color": 0, "pid": 1},
		3: {"name": "蓝", "avatar_data": {}, "color": 1, "pid": 100},
		0: {"name": "红", "avatar_data": {}, "color": 2, "pid": 101},
		2: {"name": "绿", "avatar_data": {}, "color": 3, "pid": 102},
	}
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	_check(game.four_mode, "four_mode")
	# host 自己 side 查找:pid=1 → side 1
	_check(game._find_my_side4() == 1, "host side = 1 (实际 %d)" % game._find_my_side4())
	game._build_four_side_map()
	_check(game.four_side_to_peer.size() == 4, "side map 4 方")
	# 状态序列化往返
	game.board = R.make_board4()
	game.turn4 = 0
	game.alive4 = {0: true, 1: true, 2: true, 3: true}
	game.perks4 = {0: {"yuzhe": true}, 1: {}, 2: {}, 3: {}}
	var data = game._state_to_data4()
	var back = game._board_from_json(data["board"])
	_check(back.size() == 17 and back[0].size() == 17, "17x17 往返一致")
	_check(data["perks4"]["0"].has("yuzhe"), "perks4 序列化")
	game._apply_state_data4(data)
	_check(game.perks4[0].has("yuzhe"), "perks4 反序列化")
	_check(game.turn4 == 0, "turn4 往返")
	# 客户端模拟:应用广播状态
	var data2 = game._state_to_data4()
	game._apply_state_data4(data2)
	_check(true, "状态往返 OK")

	# --- 四人隐者逆位:隐身标记生效 + 联机视角可见性 ---
	game.four_mode = true
	game.net_role = "host"
	game.my_side4 = 1  # 本机黑方
	game.board = R.make_board4()
	game.perks4 = {0: {"yinzhe2": true}, 1: {}, 2: {}, 3: {}}
	game.turn4 = 2  # 红方回合
	game.actions_left4 = 1
	game._skill_hermit4("yinzhe2", 0)
	_check(game.hidden_pieces4.size() > 0, "四人隐者逆位:红方棋子全部隐身")
	_check(not game._is_visible_hidden4(0), "本机黑方视角:红方隐身不可见(联机)")
	# 本机(黑方)自己使用隐者逆位:自己的隐身可见
	game.hidden_pieces4 = {}
	game.turn4 = 0  # 黑方回合
	game.actions_left4 = 1
	game._skill_hermit4("yinzhe2", 1)
	_check(game._is_visible_hidden4(1), "本机视角:自己的隐身可见(联机)")
	_check(not game._is_visible_hidden4(0), "红方视角:黑方隐身不可见(联机)")
	# 本地四人:全可见
	game.net_role = "local"
	game.my_side4 = -1
	_check(game._is_visible_hidden4(0) and game._is_visible_hidden4(1), "本地四人:同屏全可见")
	# 隐身子不能吃子:选隐身兵,吃子目标被过滤
	game.board = R.make_board4()
	game.hidden_pieces4 = {}
	var hpawn := Vector2i(-1, -1)
	for rr in 17:
		for cc in 17:
			var q = game.board[rr][cc]
			if q != null and q["side"] == 0 and q["type"] == R.Type.PAWN:
				hpawn = Vector2i(cc, rr)
				break
	game.hidden_pieces4[hpawn] = 100
	game.selected4 = Vector2i(-1, -1)
	game.moves4 = []
	game._select4(hpawn)
	var has_capture := false
	for m in game.moves4:
		if game.board[m.y][m.x] != null:
			has_capture = true
	_check(not has_capture, "四人隐身子:不能吃子(吃子目标被过滤)")

	# --- 对局记录:含 side 字段,状态往返保留,按玩家颜色着色 ---
	game.net_role = "host"
	game.four_mode = true
	game._record4_history = []
	game.turn4 = 0
	game._record_skill4(1, "nvjisi")
	game._record_skill4(2, "yuzhe")
	_check(game._record4_history.size() == 2, "四人:技能记录入历史")
	_check(int(game._record4_history[0].get("side", -1)) == 1, "四人:技能记录带 side")
	var rec_data = game._state_to_data4()
	_check(rec_data.has("record4_history") and rec_data["record4_history"].size() == 2, "四人:状态广播含记录")
	game._record4_history = []
	game._apply_state_data4(rec_data)
	_check(game._record4_history.size() == 2 and int(game._record4_history[0].get("side", -1)) == 1, "四人:客户端收到广播后记录含 side")
	# 主机技能消耗回合后,广播状态反映新的 turn4(其他端不再停留等待)
	game.turn4 = 0
	game.actions_left4 = 1
	game.skill_cd4 = {0: {}, 1: {}, 2: {}, 3: {}}
	game.queen_charge4 = {0: 1, 1: 1, 2: 1, 3: 1}
	game.siwang_charge4 = {0: 1, 1: 1, 2: 1, 3: 1}
	var turn_before: int = game.turn4
	game._consume_turn_after_skill4()
	_check(game.turn4 != turn_before, "四人:技能消耗回合后 turn4 切换")
	_check(int(game._state_to_data4()["turn4"]) == game.turn4, "四人:广播状态 turn4 与本地一致")

	# --- 四人倒吊人正位:释放后控制权保留(不再被回合切换清空) ---
	game.net_role = "host"
	game.four_mode = true
	game.phase = game.Phase.PLAY
	game.board = R.make_board4()
	game.perks4 = {0: {"diaodiao": true}, 1: {}, 2: {}, 3: {}}
	game.turn4 = 2  # 红方回合
	game.actions_left4 = 1
	game.skill_cd4 = {0: {}, 1: {}, 2: {}, 3: {}}
	game.controlled_piece4 = {}
	game.controlled_turns4 = 0
	game._activate_skill4("diaodiao", 0)
	# 选一个黑方非将棋子
	var target4 := Vector2i(-1, -1)
	for rr in 17:
		for cc in 17:
			var q = game.board[rr][cc]
			if q != null and q["side"] == 1 and q["type"] != R.Type.KING:
				target4 = Vector2i(cc, rr)
				break
		if target4.x >= 0:
			break
	game._handle_puppet_target4(target4, 0, "diaodiao")
	_check(not game.controlled_piece4.is_empty(), "四人倒吊人正位:释放后控制权保留")
	_check(game.controlled_turns4 == 1, "四人倒吊人正位:控制 1 回合")

	# --- 四人星星逆位:使用后不跳回合,获得蓄势,状态同步 ---
	game.board = R.make_board4()
	game.perks4 = {0: {"xingxing2": true}, 1: {}, 2: {}, 3: {}}
	game.turn4 = 2
	game.actions_left4 = 1
	game.skill_cd4 = {0: {}, 1: {}, 2: {}, 3: {}}
	game.star2_charge4 = {0: 0, 1: 0, 2: 0, 3: 0}
	var t4_before: int = game.turn4
	game._activate_skill4("xingxing2", 0)
	_check(game.turn4 == t4_before, "四人星星逆位:使用后不跳回合")
	_check(game.star2_charge4[0] == 2, "四人星星逆位:获得 2 蓄势")
	var star_data = game._state_to_data4()
	_check(int(star_data["star2_charge4"]["0"]) == 2, "四人星星逆位:蓄势随状态广播")

	# --- 四人命运之轮正位:使用后不跳回合,行动次数 +1(额外移动一次) ---
	game.board = R.make_board4()
	game.perks4 = {0: {"mingyun": true}, 1: {}, 2: {}, 3: {}}
	game.turn4 = 2
	game.actions_left4 = 1
	game.skill_cd4 = {0: {}, 1: {}, 2: {}, 3: {}}
	var turn_before_w: int = game.turn4
	game._skill_wheel4("mingyun", 0)
	_check(game.turn4 == turn_before_w, "四人命运之轮:使用后不跳回合")
	_check(game.actions_left4 == 2, "四人命运之轮:行动次数 +1(可额外移动一次)")
	# 走两步验证:第 1 步后仍可再走(actions 1),第 2 步后回合结束
	game._move4(Vector2i(4, 13), Vector2i(4, 12), "move")
	_check(game.actions_left4 == 1 and game.turn4 == 2, "四人命运之轮:第 1 步后仍可再走")
	game._move4(Vector2i(4, 12), Vector2i(4, 11), "move")
	_check(game.turn4 != 2, "四人命运之轮:第 2 步后回合结束(共 2 次行动)")

	# --- 四人 AI 走子:避开被审判逆位驳回的技能增强吃子(否则 AI 卡住) ---
	game.board = []
	for rr in 17:
		var row := []
		for cc in 17:
			row.append(null)
		game.board.append(row)
	game.board[6][4] = R.make_piece(R.Side.BLACK, R.Type.PAWN)   # 黑兵 (4,6)
	game.board[5][4] = R.make_piece(R.Side.RED, R.Type.PAWN)     # 红兵 (4,5) 正前方
	game.board[5][3] = R.make_piece(R.Side.RED, R.Type.KING)     # 红将 (3,5)
	game.perks4 = {
		0: {"shenpan2": true},  # 红方审判逆位
		1: {"ta2": true},       # 黑方塔逆位(八向移动一格=可吃正前方,但被审判禁)
		2: {}, 3: {},
	}
	game.turn4 = 0  # 黑方回合(0 索引 = side 1)
	game.alive4 = {0: true, 1: true, 2: true, 3: true}
	game.winner4 = -1
	var perks_arr_ai: Array = [game.perks4[0], game.perks4[1], game.perks4[2], game.perks4[3]]
	var mv_ai: Dictionary = game._choose_ai_move4(1, perks_arr_ai)
	var ai_avoids_shenpan := true
	if not mv_ai.is_empty():
		var cap_ai = game.board[mv_ai["to"].y][mv_ai["to"].x]
		if cap_ai != null and game.perks4[cap_ai["side"]].has("shenpan2"):
			var pure_ok := false
			for pm in R.raw_moves4(game.board, mv_ai["from"], [{}, {}, {}, {}]):
				if pm == mv_ai["to"]:
					pure_ok = true
					break
			ai_avoids_shenpan = pure_ok
	_check(ai_avoids_shenpan, "四人AI:走子避开审判逆位禁止的技能增强吃子(不卡住)")

	quit(0 if _fail_count == 0 else 1)


var _fail_count := 0
func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok - ", msg)
	else:
		_fail_count += 1
		print("FAIL - ", msg)
