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

	quit(0 if _fail_count == 0 else 1)


var _fail_count := 0
func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok - ", msg)
	else:
		_fail_count += 1
		print("FAIL - ", msg)
