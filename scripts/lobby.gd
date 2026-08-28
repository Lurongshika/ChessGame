# 等候大厅:创建/加入房间后进入,显示房间信息与玩家列表(头像/名字/棋子颜色16色)
extends Control

const Profile := preload("res://scripts/profile_util.gd")
const ChatPanel := preload("res://scripts/chat_panel.gd")
const CustomOptions := preload("res://scripts/custom_options.gd")

# 16 种棋子颜色预设(Global 共享)
const COLORS16 := Global.COLORS16

var players := {}      # peer_id -> {name, avatar_data, color}
var my_peer := 1
var lobby_label: Label
var players_box: VBoxContainer
var color_box: HBoxContainer
var start_btn: Button
var chat: Panel
var info_label: Label  # 左侧房间信息(加入端同步)
var custom_opts: Panel  # 自定义对局规则面板
var _font_cache: Font


func _font() -> Font:
	if _font_cache == null:
		_font_cache = load("res://fonts/zpix.ttf")
	return _font_cache


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.08, 0.07)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := _make_label("等候大厅", 36, Color(0.95, 0.85, 0.6))
	title.position = Vector2(0, 14)
	title.size = Vector2(1280, 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	# 左侧:房间对局信息
	var info_bg := ColorRect.new()
	info_bg.color = Color(0.13, 0.12, 0.11)
	info_bg.position = Vector2(20, 80)
	info_bg.size = Vector2(300, 560)
	add_child(info_bg)
	var info_title := _make_label("房间信息", 22, Color(0.9, 0.8, 0.6))
	info_title.position = Vector2(36, 100)
	info_title.size = Vector2(260, 34)
	add_child(info_title)
	var mode_text := "技能模式" if not Global.standard_mode else "标准模式"
	var players_text := "%d 人" % (2 if Global.game_mode != "four" else 4)
	info_label = _make_label("对局人数: %s\n对局模式: %s\n房间号: %d" % [players_text, mode_text, Global.port], 18, Color(0.85, 0.82, 0.75))
	info_label.position = Vector2(36, 150)
	info_label.size = Vector2(280, 120)
	add_child(info_label)
	lobby_label = _make_label("", 18, Color(0.9, 0.88, 0.82))
	lobby_label.position = Vector2(36, 300)
	lobby_label.size = Vector2(280, 60)
	add_child(lobby_label)

	# 右侧:玩家列表(纵向)
	var list_bg := ColorRect.new()
	list_bg.color = Color(0.12, 0.11, 0.1)
	list_bg.position = Vector2(350, 80)
	list_bg.size = Vector2(700, 400)
	add_child(list_bg)
	var list_title := _make_label("玩家", 22, Color(0.9, 0.8, 0.6))
	list_title.position = Vector2(370, 92)
	list_title.size = Vector2(200, 34)
	add_child(list_title)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(370, 130)
	scroll.size = Vector2(660, 340)
	add_child(scroll)
	players_box = VBoxContainer.new()
	players_box.custom_minimum_size = Vector2(620, 0)
	players_box.add_theme_constant_override("separation", 8)
	scroll.add_child(players_box)

	# 底部:16 色选择板
	var color_title := _make_label("选择己方棋子颜色(已被选择则禁用)", 18, Color(0.9, 0.8, 0.6))
	color_title.position = Vector2(370, 490)
	color_title.size = Vector2(400, 30)
	add_child(color_title)
	color_box = HBoxContainer.new()
	color_box.position = Vector2(370, 525)
	color_box.add_theme_constant_override("separation", 8)
	add_child(color_box)
	_build_color_palette()

	# 开始/准备按钮(主机=开始对局,加入方=准备)
	if Global.net_role == "host":
		start_btn = _make_button("开始对局", Vector2(540, 620), Vector2(200, 52))
		start_btn.pressed.connect(_start_game)
	else:
		start_btn = _make_button("准备", Vector2(540, 620), Vector2(200, 52))
		start_btn.pressed.connect(_request_ready)
	add_child(start_btn)
	var back := _make_button("返回菜单", Vector2(1280 - 140 - 20, 620), Vector2(140, 44))
	back.pressed.connect(func():
		multiplayer.multiplayer_peer = null
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	)
	add_child(back)

	# 聊天面板(左下角,可拖动/折叠)
	chat = ChatPanel.new()
	chat.setup(_font(), _send_chat)
	add_child(chat)

	# 聊天框上方:自定义选项按钮
	var opts_btn := _make_button("自定义选项", Vector2(20, 720 - 40 - 240 - 50), Vector2(150, 42))
	opts_btn.pressed.connect(func():
		if custom_opts == null:
			custom_opts = CustomOptions.new()
			custom_opts.setup(_font(), func(_r): pass)
			add_child(custom_opts)
		custom_opts.visible = true
	)
	add_child(opts_btn)
	_net_init()


func _build_color_palette() -> void:
	for i in COLORS16.size():
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(48, 48)
		var sb := StyleBoxFlat.new()
		sb.bg_color = COLORS16[i]
		sb.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		var sbp := StyleBoxFlat.new()
		sbp.bg_color = COLORS16[i].lightened(0.2)
		sbp.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("pressed", sbp)
		btn.pressed.connect(func(idx: int = i): _pick_color(idx))
		color_box.add_child(btn)


func _net_init() -> void:
	if Global.net_role == "host":
		var peer := ENetMultiplayerPeer.new()
		var max_clients: int = (2 if Global.game_mode != "four" else 4) - 1
		var err := peer.create_server(Global.port, max_clients)
		if err != OK:
			lobby_label.text = "创建房间失败(端口被占用?)"
			return
		multiplayer.multiplayer_peer = peer
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		# 主机自己加入
		var prof := Profile.to_net_data()
		players[1] = {"name": prof.get("username", "玩家"), "avatar_data": prof, "color": -1, "ready": true, "join_order": 0}
		my_peer = 1
		print("LOBBY: host ready, max=", max_clients + 1)
		_update_ui()
	else:
		var peer := ENetMultiplayerPeer.new()
		var err := peer.create_client(Global.server_ip, Global.port)
		if err != OK:
			lobby_label.text = "无法连接服务器"
			return
		multiplayer.multiplayer_peer = peer
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(func(): lobby_label.text = "连接失败")


func _on_connected() -> void:
	print("LOBBY: client connected to host")
	my_peer = multiplayer.get_unique_id()
	# 客户端:把自己的资料发给主机
	var prof := Profile.to_net_data()
	send_profile.rpc_id(1, prof.get("username", "玩家"), prof)


@rpc("any_peer", "reliable")
func send_profile(name: String, avatar_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	# 按加入顺序:已有人数作为序号(host=0)
	var max_order := 0
	for p2 in players:
		max_order = maxi(max_order, int(players[p2].get("join_order", 0)))
	players[pid] = {"name": name, "avatar_data": avatar_data, "color": -1, "join_order": max_order + 1}
	# 自动按颜色偏好分配(冲突顺延),玩家未手动选色时生效
	_auto_assign_color(pid, avatar_data.get("color_prefs", []))
	_update_ui()
	sync_room_info.rpc(Global.game_mode, Global.standard_mode)
	_sync_players.rpc(_players_to_data())
	if Global.net_role == "host" and _has_arg("--auto-start"):
		var need := 2 if Global.game_mode != "four" else 4
		if players.size() >= need:
			call_deferred("_start_game")


@rpc("authority", "call_local", "reliable")
func sync_room_info(mode: String, standard: bool) -> void:
	Global.game_mode = mode
	Global.standard_mode = standard
	_update_room_count()
	# 刷新左侧房间信息(加入端初始不知人数/模式)
	if info_label != null:
		var mtext := "技能模式" if not standard else "标准模式"
		var ptext := "%d 人" % (2 if mode != "four" else 4)
		info_label.text = "对局人数: %s\n对局模式: %s\n房间号: %d" % [ptext, mtext, Global.port]


@rpc("authority", "call_local", "reliable")
func _sync_players(data: Dictionary) -> void:
	# 主机把序列化好的玩家状态广播,客户端直接应用(客户端本地 players 为空,不能自行生成)
	_apply_players(data)
	_update_ui()


func _on_peer_connected(pid: int) -> void:
	print("LOBBY: peer connected pid=", pid)
	lobby_label.text = "玩家已连接,等待资料..."


func _on_peer_disconnected(pid: int) -> void:
	players.erase(pid)
	_update_ui()


func _players_to_data() -> Dictionary:
	var data := {}
	for pid in players:
		data[str(pid)] = {
			"name": players[pid]["name"],
			"avatar": players[pid]["avatar_data"],
			"color": players[pid]["color"],
			"ready": bool(players[pid].get("ready", false)),
			"join_order": int(players[pid].get("join_order", 0)),
		}
	return data


func _apply_players(data: Dictionary) -> void:
	players = {}
	for pid in data:
		var p: Dictionary = data[pid]
		players[int(pid)] = {"name": p["name"], "avatar_data": p["avatar"], "color": int(p["color"]), "ready": bool(p.get("ready", false)), "join_order": int(p.get("join_order", 0))}
		if int(pid) == my_peer:
			Global.my_color = int(p["color"])
	# 更新准备按钮文本(加入方)
	if start_btn != null and Global.net_role != "host":
		var my_ready: bool = bool(players.get(my_peer, {}).get("ready", false))
		start_btn.text = "取消准备" if my_ready else "准备"


func _pick_color(idx: int) -> void:
	if my_peer <= 0:
		return
	# 该颜色已被其他玩家选择则禁用
	for pid in players:
		if pid != my_peer and players[pid]["color"] == idx:
			lobby_label.text = "该颜色已被选择"
			return
	if Global.net_role == "host":
		if players.has(my_peer):
			players[my_peer]["color"] = idx
		Global.my_color = idx
		_sync_players.rpc(_players_to_data())
	else:
		request_color.rpc_id(1, idx)


# 按颜色偏好自动选色:偏好逐个尝试,已被占用则顺延到下一个偏好;全占用则随机
func _auto_assign_color(pid: int, prefs: Array) -> void:
	if players.has(pid) and players[pid].get("color", -1) >= 0:
		return  # 已手动选色
	var used := {}
	for p2 in players:
		if p2 != pid and players[p2].get("color", -1) >= 0:
			used[players[p2]["color"]] = true
	var assigned := -1
	for v in prefs:
		var ci := int(v)
		if ci >= 0 and ci < Global.COLORS16.size() and not used.has(ci):
			assigned = ci
			break
	if assigned < 0:
		# 随机兜底
		var avail: Array = []
		for i in Global.COLORS16.size():
			if not used.has(i):
				avail.append(i)
		if avail.is_empty():
			avail = range(Global.COLORS16.size())
		assigned = avail.pick_random()
	if players.has(pid):
		players[pid]["color"] = assigned


# 加入方:点击准备(可取消)
func _request_ready() -> void:
	if my_peer <= 0:
		return
	if Global.net_role == "client":
		request_ready_state.rpc_id(1)
	else:
		if players.has(my_peer):
			players[my_peer]["ready"] = not bool(players[my_peer].get("ready", false))
		_sync_players.rpc(_players_to_data())


# 发送聊天:host 权威转发(客户端发到主机,主机显示并广播给所有人)
func _send_chat(text: String) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if Global.net_role == "host":
		chat.add_message(players.get(1, {}).get("name", "主机"), text)
		send_chat_relay.rpc(players.get(1, {}).get("name", "主机"), text)
	else:
		send_chat.rpc_id(1, text)


@rpc("any_peer", "reliable")
func send_chat(text: String) -> void:
	if Global.net_role != "host":
		return
	# 发信人名字
	var who: String = "玩家"
	var pid := multiplayer.get_remote_sender_id()
	if players.has(pid):
		who = players[pid]["name"]
	chat.add_message(who, text)
	# 广播给所有客户端(含发信方)
	send_chat_relay.rpc(who, text)


@rpc("authority", "reliable")
func send_chat_relay(who: String, text: String) -> void:
	chat.add_message(who, text)


@rpc("any_peer", "reliable")
func request_ready_state() -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	if not players.has(pid):
		return
	players[pid]["ready"] = not bool(players[pid].get("ready", false))
	_sync_players.rpc(_players_to_data())


@rpc("any_peer", "reliable")
func request_color(idx: int) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	if not players.has(pid):
		return
	for p in players:
		if p != pid and players[p]["color"] == idx:
			return  # 已占用
	players[pid]["color"] = idx
	_sync_players.rpc(_players_to_data())


func net_avatar(data: Dictionary, size: int) -> Texture2D:
	# 从网络资料解码头像:自定义头像 PNG 或颜色图标
	if data.has("avatar_png") and not (data["avatar_png"] as PackedByteArray).is_empty():
		var img := Image.new()
		if img.load_png_from_buffer(data["avatar_png"]) == OK:
			img.resize(size, size, Image.INTERPOLATE_LANCZOS)
			return ImageTexture.create_from_image(img)
	var c: Array = data.get("color", [0.35, 0.6, 0.9])
	return Profile.color_icon(Color(float(c[0]), float(c[1]), float(c[2])), size)


func _update_ui() -> void:
	if players_box == null:
		return
	for child in players_box.get_children():
		players_box.remove_child(child)
		child.queue_free()
	var order: Array = players.keys()
	order.sort_custom(func(a, b): return int(players[a].get("join_order", 0)) < int(players[b].get("join_order", 0)))
	for pid in order:
		var p: Dictionary = players[pid]
		players_box.add_child(_player_row(pid, p))
	_update_room_count()
	# 颜色板禁用已被选的
	if color_box != null:
		for i in COLORS16.size():
			var btn: Button = color_box.get_child(i)
			var used := false
			for pid in players:
				if players[pid]["color"] == i:
					used = true
					break
			btn.disabled = used and (players.get(my_peer, {}).get("color", -1) != i)


# 房间人数显示(四人在 players 应用后统一刷新,避免 sync_room_info 先到导致旧计数)
func _update_room_count() -> void:
	if lobby_label == null:
		return
	if Global.game_mode == "four":
		lobby_label.text = "四人模式 — 等待玩家加入(%d/4)" % players.size()
	elif lobby_label.text == "":
		lobby_label.text = "双人模式 — 等待玩家加入(%d/2)" % players.size()


func _player_row(pid: int, p: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(620, 56)
	row.add_theme_constant_override("separation", 12)
	var color_idx: int = p["color"]
	# 头像框(描边 = 棋子颜色)
	var avatar_frame := Panel.new()
	avatar_frame.custom_minimum_size = Vector2(54, 54)
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.22, 0.22, 0.27)
	fsb.set_corner_radius_all(8)
	if color_idx >= 0:
		fsb.border_color = COLORS16[color_idx]
		fsb.set_border_width_all(3)
	avatar_frame.add_theme_stylebox_override("panel", fsb)
	var avatar := TextureRect.new()
	avatar.position = Vector2(3, 3)
	avatar.size = Vector2(48, 48)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex := net_avatar(p["avatar_data"], 48)
	if tex != null:
		avatar.texture = tex
	avatar_frame.add_child(avatar)
	row.add_child(avatar_frame)
	# 名字
	var name_label := _make_label(p["name"], 20, Color(0.9, 0.9, 0.85))
	name_label.custom_minimum_size = Vector2(200, 48)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)
	# 当前颜色块 + 是否自己 + 准备状态
	var color_txt := "未选色"
	if color_idx >= 0:
		color_txt = "颜色 %d" % (color_idx + 1)
	var suffix := " (我)" if pid == my_peer else ""
	var ready_txt := "已准备" if bool(p.get("ready", false)) else "未准备"
	var info := _make_label("%s%s  [%s]" % [color_txt, suffix, ready_txt], 16, Color(0.8, 0.75, 0.65))
	info.custom_minimum_size = Vector2(260, 48)
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(info)
	return row


func _has_arg(prefix: String) -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return true
	return false


func _start_game() -> void:
	if Global.net_role != "host":
		return
	# 四人模式:需加入端全部准备(房主无需准备;--auto-start 测试自动开局跳过)
	if Global.game_mode == "four" and not _has_arg("--auto-start"):
		for pid in players:
			if pid == 1:
				continue  # 房主不需要准备
			if not bool(players[pid].get("ready", false)):
				lobby_label.text = "还有玩家未准备"
				return
	# 未选色的玩家随机分配(不冲突)
	var used_colors := {}
	for pid in players:
		if players[pid]["color"] >= 0:
			used_colors[players[pid]["color"]] = true
	for pid in players:
		if players[pid]["color"] < 0:
			var avail: Array = []
			for i in Global.COLORS16.size():
				if not used_colors.has(i):
					avail.append(i)
			if avail.is_empty():
				avail = range(Global.COLORS16.size())
			var pick: int = avail.pick_random()
			players[pid]["color"] = pick
			used_colors[pick] = true
	# 分配 side → 颜色(双人:先连=红,后=黑;四人:按顺序)
	Global.player_colors = {}
	var order: Array = players.keys()
	order.sort()
	var sides: Array
	if Global.game_mode == "four":
		sides = [1, 3, 0, 2]  # 上黑 右蓝 下红 左绿
	else:
		sides = [0, 1]
	# 组装四方玩家表(side -> 信息),供对局内四角显示头像/名字
	var lobby_players := {}
	for i in mini(order.size(), sides.size()):
		var pid: int = order[i]
		var side: int = sides[i]
		Global.player_colors[side] = players[pid]["color"]
		lobby_players[side] = {
			"name": players[pid]["name"],
			"avatar_data": players[pid]["avatar_data"],
			"color": players[pid]["color"],
			"pid": pid,
		}
	Global.from_lobby = true
	start_game.rpc(Global.player_colors, Global.game_mode, Global.standard_mode, lobby_players)


@rpc("authority", "call_local", "reliable")
func start_game(colors: Dictionary, mode: String, standard: bool, lobby_players: Dictionary = {}) -> void:
	Global.from_lobby = true
	Global.player_colors = colors
	# 加入方必须同步房间模式(四人/标准),否则会按双人 pvp 逻辑等待 assign_perks 卡死
	Global.game_mode = mode
	Global.standard_mode = standard
	Global.lobby_players = lobby_players
	# 保持连接,直接进入对局(game 复用大厅连接)
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _make_button(text: String, pos: Vector2, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.add_theme_font_override("font", _font())
	b.add_theme_font_size_override("font_size", 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.22, 0.28)
	sb.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	var sbp := StyleBoxFlat.new()
	sbp.bg_color = Color(0.3, 0.33, 0.42)
	sbp.set_corner_radius_all(6)
	b.add_theme_stylebox_override("pressed", sbp)
	return b
