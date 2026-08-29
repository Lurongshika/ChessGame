extends Node

# 全局单例:记录对战模式与联机参数
var game_mode := "pvp"      # "pvp" 双人 / "ai" 人机(本地)
var net_role := "local"     # "local" 本地 / "host" 联机主机(红方) / "client" 联机客户端(黑方)
var server_ip := ""         # 联机客户端:目标主机 IP
var port := 7777            # 联机端口(内网穿透时按穿透配置修改)
var load_slot := 0          # 主菜单「选择存档」:进入游戏场景后加载指定槽位(0=不加载)
var standard_mode := false  # 标准模式:双方不使用任何技能
var perk_pool := "all"      # 技能池:all(44 个,正位+逆位)
var demo_perk := ""         # 技能图鉴:当前演示的技能 id(非空时进入演示对局)
var my_color := -1          # 大厅:己方选的棋子颜色索引(0-15)
var player_colors := {}     # 对局:side -> 棋子颜色索引(大厅分配)
var lobby_players := {}     # 对局:side -> {name, avatar_data, color} 四方玩家信息(大厅传入)
var game_rules := {}        # 自定义对局规则(大厅选项): win_mode/king_down/promotion/kill_count
var from_lobby := false     # 是否从等候大厅进入对局(复用大厅连接)

# 设置(用户可调,持久化到 user://settings.json)
const SETTINGS_PATH := "user://settings.json"
var crt_strength := 0.4     # CRT 效果强度(0.0-1.0,默认 40%)
var crt_aberration := 0.0005  # CRT 红蓝偏移(色差,0.0-0.01,默认 0.0005)
var crt_curve := 3.85       # CRT 画面曲率(1.0-20.0,越小越弯,默认 85%≈3.85)

# 16 种棋子颜色预设(大厅选色板与对局棋子共用)
# 8 种颜色:红蓝绿紫粉青黑橙(黑=黑方棋子色,用于玩家区分)
const COLORS16 := [
	Color(0.78, 0.15, 0.12), Color(0.1, 0.35, 0.78), Color(0.1, 0.62, 0.2),
	Color(0.62, 0.2, 0.72), Color(0.95, 0.3, 0.62), Color(0.1, 0.82, 0.85),
	Color(0.2, 0.18, 0.16), Color(0.95, 0.6, 0.1),
]


# --- 扁平按钮样式(无黑底,悬浮字变黄) ---
static func style_flat_button(b: Button) -> void:
	# 透明背景(无黑底)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	normal.set_corner_radius_all(4)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", normal)
	b.add_theme_stylebox_override("focus", normal)
	b.add_theme_stylebox_override("hover_pressed", normal)
	# 字体颜色:默认浅色,悬浮变黄
	b.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.3))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.85, 0.2))
	b.add_theme_color_override("font_focus_color", Color(0.85, 0.82, 0.75))


# 创建扁平按钮(无黑底,悬浮变黄)
static func flat_button(text: String, pos: Vector2, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	style_flat_button(b)
	return b


# --- UI 出场动画(所有界面:主菜单/大厅/图鉴/设置等,含返回上一级) ---
# 遍历场景内所有 Button,按纵向位置排序,依次淡入 + 上浮
static func animate_ui_in(root: Node) -> void:
	var buttons: Array = []
	_collect_buttons(root, buttons)
	# 按 y 位置排序(从上到下依次出现)
	buttons.sort_custom(func(a, b): return a.global_position.y < b.global_position.y)
	for i in buttons.size():
		var b: Button = buttons[i]
		# 已透明(如菜单动画已处理)则跳过
		if b.modulate.a <= 0.01:
			continue
		b.modulate.a = 0.0
		var tw := root.create_tween()
		tw.tween_interval(i * 0.06)
		tw.tween_property(b, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		# 容器内按钮(由容器布局)只淡入,不动位置;自由定位按钮淡入+上浮
		if not _in_container(b):
			var orig_pos: Vector2 = b.position
			b.position = orig_pos + Vector2(0, 16)
			tw.parallel().tween_property(b, "position", orig_pos, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func _in_container(b: Control) -> bool:
	var parent := b.get_parent()
	return parent is VBoxContainer or parent is HBoxContainer or parent is GridContainer


static func _collect_buttons(node: Node, out: Array) -> void:
	if node is Button:
		out.append(node)
	for child in node.get_children():
		_collect_buttons(child, out)


# --- 音频(音效 + 循环 BGM) ---
var _audio_player: AudioStreamPlayer
var _bgm_player: AudioStreamPlayer
var _sfx_cache := {}


func _setup_audio() -> void:
	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)
	_bgm_player = AudioStreamPlayer.new()
	add_child(_bgm_player)


# 播放音效(缓存加载)
func play_sfx(name: String, volume_db: float = 0.0) -> void:
	if _audio_player == null:
		return
	if not _sfx_cache.has(name):
		var path := "res://assets/sounds/%s.mp3" % name
		if not ResourceLoader.exists(path):
			return
		_sfx_cache[name] = load(path)
	var stream: AudioStream = _sfx_cache[name]
	if stream == null:
		return
	_audio_player.stream = stream
	_audio_player.volume_db = volume_db
	_audio_player.play()


# 循环播放 BGM
func play_bgm(volume_db: float = -8.0) -> void:
	if _bgm_player == null:
		return
	if _bgm_player.playing:
		return
	_bgm_player.stream = load("res://assets/sounds/bgm.mp3")
	_bgm_player.volume_db = volume_db
	_bgm_player.play()


func stop_bgm() -> void:
	if _bgm_player != null:
		_bgm_player.stop()


# --- CRT 后处理(全局,参考 CrtTypewriter) ---
var _crt_layer: CanvasLayer
var _crt_rect: ColorRect


func _setup_crt() -> void:
	# CRT 全屏后处理层(layer 99,在过渡层 100 之下)
	_crt_layer = CanvasLayer.new()
	_crt_layer.layer = 99
	add_child(_crt_layer)
	_crt_rect = ColorRect.new()
	_crt_rect.color = Color(1, 1, 1, 1)
	_crt_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/crt.gdshader")
	_crt_rect.material = mat
	_crt_layer.add_child(_crt_rect)
	# 应用已保存的 CRT 设置
	_apply_crt_params()


# 开关 CRT 效果(默认开)
func set_crt_enabled(enabled: bool) -> void:
	if _crt_rect != null:
		_crt_rect.visible = enabled


# 应用 CRT 强度/色差/曲率到 shader
func _apply_crt_params() -> void:
	if _crt_rect == null or not (_crt_rect.material is ShaderMaterial):
		return
	var mat := _crt_rect.material as ShaderMaterial
	mat.set_shader_parameter("strength", crt_strength)
	mat.set_shader_parameter("aberration", crt_aberration)
	mat.set_shader_parameter("curve_val", crt_curve)


# 设置 CRT 效果强度(0.0-1.0),保存到本地设置
func set_crt_strength(v: float) -> void:
	crt_strength = clampf(v, 0.0, 1.0)
	_apply_crt_params()
	_save_settings()


# 设置 CRT 红蓝偏移(0.0-0.01),保存到本地设置
func set_crt_aberration(v: float) -> void:
	crt_aberration = clampf(v, 0.0, 0.01)
	_apply_crt_params()
	_save_settings()


# 设置 CRT 画面曲率(1.0-20.0,越大越平),保存到本地设置
func set_crt_curve(v: float) -> void:
	crt_curve = clampf(v, 1.0, 20.0)
	_apply_crt_params()
	_save_settings()


# 从 user://settings.json 加载设置
func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		return
	if data.has("crt_strength"):
		crt_strength = clampf(float(data["crt_strength"]), 0.0, 1.0)
	if data.has("crt_aberration"):
		crt_aberration = clampf(float(data["crt_aberration"]), 0.0, 0.01)
	if data.has("crt_curve"):
		crt_curve = clampf(float(data["crt_curve"]), 1.0, 20.0)


# 保存设置到 user://settings.json
func _save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"crt_strength": crt_strength,
		"crt_aberration": crt_aberration,
		"crt_curve": crt_curve,
	}))
	f.close()


# --- 场景过渡(淡入淡出) ---
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _fade_alpha := 1.0
var _fade_target := 0.0
var _fade_speed := 3.2
var _pending_scene := ""
var _switching := false


func _ready() -> void:
	_setup_audio()
	# 加载用户设置(CRT 等)
	_load_settings()
	# CRT 后处理层(全屏,参考 CrtTypewriter 效果)
	_setup_crt()
	# 过渡层(最高层,常驻)
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 不拦截鼠标:透明时按钮可正常点击
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)
	set_process(true)
	# 开局淡入(从黑到透明)
	_fade_alpha = 1.0
	_fade_target = 0.0
	# 解析命令行参数(自动化测试用)
	_parse_cmdline_args()


func _process(delta: float) -> void:
	if absf(_fade_alpha - _fade_target) < 0.005:
		_fade_alpha = _fade_target
	else:
		_fade_alpha = move_toward(_fade_alpha, _fade_target, _fade_speed * delta)
	_fade_rect.color.a = _fade_alpha
	# 淡出完成且有待切换场景
	if _switching and _fade_alpha >= 1.0 and _pending_scene != "":
		_switching = false
		var sc := _pending_scene
		_pending_scene = ""
		get_tree().change_scene_to_file(sc)
		# 新场景就绪后淡入
		_fade_target = 0.0


# 带过渡的场景切换:淡出 → 切换 → 淡入
func change_scene_with_fade(path: String) -> void:
	if _pending_scene != "":
		return
	_pending_scene = path
	_switching = true
	_fade_target = 1.0


# 解析命令行参数(用于自动化测试):--net=host/client --ip=192.168.x.x --port=7777 --mode=pvp/ai --slot=1 --pool=normal/advanced
func _parse_cmdline_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--net="):
			net_role = arg.trim_prefix("--net=")
		elif arg.begins_with("--ip="):
			server_ip = arg.trim_prefix("--ip=")
		elif arg.begins_with("--port="):
			var p := int(arg.trim_prefix("--port="))
			if p > 0:
				port = p
		elif arg.begins_with("--mode="):
			game_mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--pool="):
			perk_pool = arg.trim_prefix("--pool=")
		elif arg.begins_with("--slot="):
			load_slot = int(arg.trim_prefix("--slot="))
	# 客户端未指定 IP 时默认本机回环(本机双开联机测试)
	if net_role == "client" and server_ip.is_empty():
		server_ip = "127.0.0.1"
