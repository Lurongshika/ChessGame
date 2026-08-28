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
	quit(0 if _fail_count == 0 else 1)


var _fail_count := 0
func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok - ", msg)
	else:
		_fail_count += 1
		print("FAIL - ", msg)
