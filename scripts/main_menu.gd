extends Control

const BgLayer := preload("res://scripts/bg_layer.gd")
const Profile := preload("res://scripts/profile_util.gd")

func _ready() -> void:
	var bg := BgLayer.new()
	add_child(bg)

	var title := _label("秘弈", 64, Color(0.95, 0.85, 0.6))
	title.position = Vector2(0, 100)
	title.size = Vector2(1280, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	# 继续对局(有存档时显示)
	if _has_any_save():
		var btn0 := _button("继续对局", Vector2(540, 240))
		btn0.pressed.connect(func(): Global.change_scene_with_fade("res://scenes/slots.tscn"))
		add_child(btn0)
		menu_btns.append(btn0)

	var btn2 := _button("人机对战", Vector2(540, 310))
	btn2.pressed.connect(_show_ai_options)
	add_child(btn2)
	menu_btns.append(btn2)

	var btn3 := _button("局域网联机", Vector2(540, 380))
	btn3.pressed.connect(_show_net_options)
	add_child(btn3)
	menu_btns.append(btn3)

	var btn4 := _button("技能图鉴", Vector2(540, 450))
	btn4.pressed.connect(func(): Global.change_scene_with_fade("res://scenes/manual.tscn"))
	add_child(btn4)
	menu_btns.append(btn4)

	var btn5 := _button("设置", Vector2(540, 520))
	btn5.pressed.connect(_show_settings)
	add_child(btn5)
	menu_btns.append(btn5)

	var btn6 := _button("退出游戏", Vector2(540, 590))
	btn6.pressed.connect(func(): get_tree().quit())
	add_child(btn6)
	menu_btns.append(btn6)

	_build_user_button()
	Global.animate_ui_in(self)

	# 自动化测试入口:--auto 时按命令行 net_role 直接进入联机对局(正常游玩不受影响)
	if _has_user_arg("--auto") and Global.net_role != "local":
		if Global.net_role == "host":
			Global.standard_mode = _has_user_arg("--standard")
		call_deferred("_auto_enter_net")


func _auto_enter_net() -> void:
	# 延迟到本帧结束再切场景,避免在 _ready 中切换导致 remove_child 报错
	Global.change_scene_with_fade("res://scenes/game.tscn")


func _has_user_arg(prefix: String) -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return true
	return false


var menu_btns: Array = []
var opt_root: Control


func _show_ai_options() -> void:
	# 人机对战:隐藏主菜单所有按钮,弹出标准/技能选择(普通/进阶)
	_set_menu_visible(false)
	opt_root = _make_option_layer()
	_add_option_button("标准模式", Vector2(540, 300), func(): _start_local_pool("ai", true, "all"))
	_add_option_button("技能模式", Vector2(540, 370), func(): _start_local_pool("ai", false, "all"))
	_add_option_button("返回", Vector2(540, 440), _close_options)


func _show_net_options() -> void:
	# 局域网联机:选择创建对战 / 加入对战
	if opt_root != null:
		opt_root.queue_free()
	_set_menu_visible(false)
	opt_root = _make_option_layer()
	_add_option_button("创建在线对战", Vector2(540, 280), _show_net_create)
	_add_option_button("加入在线对战", Vector2(540, 360), _show_net_join)
	_add_option_button("返回", Vector2(540, 440), _close_options)


# 创建在线对战:选模式/人数 → 创建房间 → 等候大厅
func _show_net_create() -> void:
	if opt_root != null:
		opt_root.queue_free()
	opt_root = _make_option_layer()
	net_mode = "skill"
	net_players = 4
	net_mode_btns = []
	var mode_title := _label("选择模式", 24, Color(0.9, 0.85, 0.75))
	mode_title.position = Vector2(0, 230)
	mode_title.size = Vector2(1280, 30)
	mode_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opt_root.add_child(mode_title)
	var skill_btn := _button("技能模式", Vector2(430, 280))
	skill_btn.pressed.connect(func(): _set_net_mode("skill"))
	opt_root.add_child(skill_btn)
	net_mode_btns.append(skill_btn)
	var std_btn := _button("标准模式", Vector2(650, 280))
	std_btn.pressed.connect(func(): _set_net_mode("standard"))
	opt_root.add_child(std_btn)
	net_mode_btns.append(std_btn)
	_refresh_net_mode_highlight()
	net_players_btns = []
	var p_title := _label("选择人数", 24, Color(0.9, 0.85, 0.75))
	p_title.position = Vector2(0, 340)
	p_title.size = Vector2(1280, 30)
	p_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opt_root.add_child(p_title)
	var p2_btn := _button("双人", Vector2(430, 390))
	p2_btn.pressed.connect(func(): _set_net_players(2))
	opt_root.add_child(p2_btn)
	net_players_btns.append(p2_btn)
	var p4_btn := _button("四人", Vector2(650, 390))
	p4_btn.pressed.connect(func(): _set_net_players(4))
	opt_root.add_child(p4_btn)
	net_players_btns.append(p4_btn)
	_refresh_net_players_highlight()
	_animate_opt_extra_buttons([skill_btn, std_btn, p2_btn, p4_btn])
	_add_option_button("创建房间", Vector2(540, 500), func():
		Global.port = Global.port
		Global.game_mode = "four" if net_players == 4 else "pvp"
		Global.standard_mode = net_mode == "standard"
		Global.perk_pool = "all"
		print("创建房间: 人数=", net_players, " 模式=", net_mode, " standard_mode=", Global.standard_mode)
		Global.net_role = "host"
		Global.change_scene_with_fade("res://scenes/lobby.tscn")
	)
	_add_option_button("返回", Vector2(540, 580), _show_net_options)


# 加入在线对战:输入 IP/端口 → 加入房间 → 等候大厅
func _show_net_join() -> void:
	if opt_root != null:
		opt_root.queue_free()
	opt_root = _make_option_layer()
	var ip_edit := LineEdit.new()
	ip_edit.placeholder_text = "对方 IP/域名(留空=本机)"
	ip_edit.position = Vector2(455, 280)
	ip_edit.size = Vector2(250, 40)
	ip_edit.add_theme_font_override("font", _font())
	ip_edit.add_theme_font_size_override("font_size", 17)
	opt_root.add_child(ip_edit)
	var port_edit := LineEdit.new()
	port_edit.text = str(Global.port)
	port_edit.placeholder_text = "端口"
	port_edit.position = Vector2(725, 280)
	port_edit.size = Vector2(100, 40)
	port_edit.add_theme_font_override("font", _font())
	port_edit.add_theme_font_size_override("font_size", 17)
	opt_root.add_child(port_edit)
	_animate_opt_extra_buttons([])
	_add_option_button("加入房间", Vector2(540, 360), func():
		Global.port = _parse_port(port_edit.text)
		Global.net_role = "client"
		var ip := ip_edit.text.strip_edges()
		Global.server_ip = ip if not ip.is_empty() else "127.0.0.1"
		Global.change_scene_with_fade("res://scenes/lobby.tscn")
	)
	_add_option_button("返回", Vector2(540, 440), _show_net_options)


# 设置:CRT 效果强度 / 红蓝偏移 / 画面曲率(实时生效并保存)
func _show_settings() -> void:
	if opt_root != null:
		opt_root.queue_free()
	_set_menu_visible(false)
	opt_root = _make_option_layer()
	var title := _label("设置", 26, Color(0.95, 0.85, 0.6))
	title.position = Vector2(0, 200)
	title.size = Vector2(1280, 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opt_root.add_child(title)

	# CRT 效果强度(0-100 → 0.0-1.0)
	var st_label := _label("CRT 效果强度", 17, Color(0.85, 0.82, 0.75))
	st_label.position = Vector2(350, 280)
	st_label.size = Vector2(180, 34)
	opt_root.add_child(st_label)
	var st_slider := HSlider.new()
	st_slider.min_value = 0
	st_slider.max_value = 100
	st_slider.step = 1
	st_slider.value = Global.crt_strength * 100.0
	st_slider.position = Vector2(550, 282)
	st_slider.size = Vector2(280, 30)
	st_slider.add_theme_font_override("font", _font())
	opt_root.add_child(st_slider)
	var st_val := _label("%d%%" % int(Global.crt_strength * 100.0), 17, Color(1.0, 0.9, 0.3))
	st_val.position = Vector2(850, 280)
	st_val.size = Vector2(90, 34)
	opt_root.add_child(st_val)
	st_slider.value_changed.connect(func(v: float):
		Global.set_crt_strength(v / 100.0)
		st_val.text = "%d%%" % int(v)
	)

	# 红蓝偏移(0-100 → 0.0-0.01)
	var ab_label := _label("红蓝偏移", 17, Color(0.85, 0.82, 0.75))
	ab_label.position = Vector2(350, 350)
	ab_label.size = Vector2(180, 34)
	opt_root.add_child(ab_label)
	var ab_slider := HSlider.new()
	ab_slider.min_value = 0
	ab_slider.max_value = 100
	ab_slider.step = 1
	ab_slider.value = Global.crt_aberration / 0.01 * 100.0
	ab_slider.position = Vector2(550, 352)
	ab_slider.size = Vector2(280, 30)
	ab_slider.add_theme_font_override("font", _font())
	opt_root.add_child(ab_slider)
	var ab_val := _label("%.4f" % Global.crt_aberration, 17, Color(1.0, 0.9, 0.3))
	ab_val.position = Vector2(850, 350)
	ab_val.size = Vector2(90, 34)
	opt_root.add_child(ab_val)
	ab_slider.value_changed.connect(func(v: float):
		var ab := v / 100.0 * 0.01
		Global.set_crt_aberration(ab)
		ab_val.text = "%.4f" % ab
	)

	# 画面曲率(0-100 → curve_val 20.0-1.0,越小越弯)
	var cv_label := _label("画面曲率", 17, Color(0.85, 0.82, 0.75))
	cv_label.position = Vector2(350, 420)
	cv_label.size = Vector2(180, 34)
	opt_root.add_child(cv_label)
	var cv_slider := HSlider.new()
	cv_slider.min_value = 0
	cv_slider.max_value = 100
	cv_slider.step = 1
	cv_slider.value = (20.0 - Global.crt_curve) / (20.0 - 1.0) * 100.0
	cv_slider.position = Vector2(550, 422)
	cv_slider.size = Vector2(280, 30)
	cv_slider.add_theme_font_override("font", _font())
	opt_root.add_child(cv_slider)
	var cv_val := _label("%d%%" % int((20.0 - Global.crt_curve) / (20.0 - 1.0) * 100.0), 17, Color(1.0, 0.9, 0.3))
	cv_val.position = Vector2(850, 420)
	cv_val.size = Vector2(90, 34)
	opt_root.add_child(cv_val)
	cv_slider.value_changed.connect(func(v: float):
		var cv := 20.0 - v / 100.0 * (20.0 - 1.0)
		Global.set_crt_curve(cv)
		cv_val.text = "%d%%" % int(v)
	)

	_animate_opt_extra_buttons([])
	_add_option_button("返回", Vector2(540, 520), _close_options)


var net_mode := "skill"
var net_mode_btns: Array = []
var net_players := 2
var net_players_btns: Array = []


func _set_net_players(n: int) -> void:
	net_players = n
	_refresh_net_players_highlight()


func _refresh_net_players_highlight() -> void:
	for i in net_players_btns.size():
		var b: Button = net_players_btns[i]
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.18, 0.22, 0.3)
		sb.set_corner_radius_all(6)
		if (i == 0 and net_players == 2) or (i == 1 and net_players == 4):
			sb.border_color = Color(0.95, 0.8, 0.2)
			sb.set_border_width_all(3)
		else:
			sb.border_color = Color(0.4, 0.37, 0.32)
			sb.set_border_width_all(1)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)


func _set_net_mode(mode: String) -> void:
	net_mode = mode
	_refresh_net_mode_highlight()


func _refresh_net_mode_highlight() -> void:
	for i in net_mode_btns.size():
		var b: Button = net_mode_btns[i]
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.18, 0.22, 0.3)
		sb.set_corner_radius_all(6)
		var modes := ["skill", "standard"]
		if i < modes.size() and net_mode == modes[i]:
			sb.border_color = Color(0.95, 0.8, 0.2)
			sb.set_border_width_all(3)
		else:
			sb.border_color = Color(0.4, 0.37, 0.32)
			sb.set_border_width_all(1)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)


func _make_option_layer() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.09, 0.78)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	return root


func _add_option_button(text: String, pos: Vector2, cb: Callable) -> void:
	var b := _button(text, pos)
	b.pressed.connect(cb)
	opt_root.add_child(b)
	_animate_option_button(b)


# 选项层按钮动画:淡入 + 上浮(依次出现)
func _animate_option_button(b: Button) -> void:
	var idx := 0
	for child in opt_root.get_children():
		if child is Button:
			idx += 1
	b.modulate.a = 0.0
	var orig_pos: Vector2 = b.position
	b.position = orig_pos + Vector2(0, 14)
	var tw := create_tween()
	tw.tween_interval((idx - 1) * 0.06)
	tw.tween_property(b, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(b, "position", orig_pos, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# 给创建/加入界面的直接按钮补动画(模式/人数/输入框等)
func _animate_opt_extra_buttons(btns: Array) -> void:
	for b in btns:
		_animate_option_button(b)
	# 输入框/滑块淡入
	for child in opt_root.get_children():
		if child is LineEdit or child is HSlider:
			child.modulate.a = 0.0
			var tw := create_tween()
			tw.tween_interval(0.1)
			tw.tween_property(child, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _close_options() -> void:
	if opt_root != null:
		opt_root.queue_free()
		opt_root = null
	_set_menu_visible(true)
	# 返回主界面:重新播放主菜单按钮入场动画(选项层已释放,避免连带动画)
	call_deferred("_replay_menu_anim")


func _replay_menu_anim() -> void:
	Global.animate_ui_in(self)


func _set_menu_visible(v: bool) -> void:
	for b in menu_btns:
		b.visible = v


func _parse_port(text: String) -> int:
	var p := int(text.strip_edges())
	if p > 0 and p <= 65535:
		return p
	return Global.port


func _build_user_button() -> void:
	# 右下角用户按钮 + 用户名
	var profile := _load_profile()
	var user_color := Color(0.35, 0.6, 0.9)
	# 头像底色取第一个颜色偏好(兼容旧 color 字段)
	var prefs: Array = profile.get("color_prefs", [])
	if not prefs.is_empty():
		var ci := int(prefs[0])
		if ci >= 0 and ci < Global.COLORS16.size():
			user_color = Global.COLORS16[ci]
	else:
		var color_data = profile.get("color", [])
		if color_data.size() == 3:
			user_color = Color(float(color_data[0]), float(color_data[1]), float(color_data[2]))
	var user_btn := Button.new()
	user_btn.position = Vector2(1280 - 72, 720 - 72)
	user_btn.size = Vector2(56, 56)
	user_btn.icon = _current_avatar_icon(profile, user_color, 40)
	user_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	user_btn.tooltip_text = "用户设置"
	user_btn.pressed.connect(func(): Global.change_scene_with_fade("res://scenes/user.tscn"))
	add_child(user_btn)

	var uname: String = profile.get("username", "")
	if uname.is_empty():
		uname = "未设置"
	var name_label := _label(uname, 12, Color(0.75, 0.72, 0.65))
	name_label.position = Vector2(1280 - 170, 720 - 28)
	name_label.size = Vector2(160, 20)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(name_label)


func _load_profile() -> Dictionary:
	if not FileAccess.file_exists("user://profile.json"):
		return {}
	var f := FileAccess.open("user://profile.json", FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		return data
	return {}


func _current_avatar_icon(profile: Dictionary, color: Color, size: int) -> Texture2D:
	# 自定义头像优先,否则用颜色头像
	if bool(profile.get("custom_avatar", false)) and FileAccess.file_exists("user://avatar.png"):
		var img := Image.new()
		if img.load("user://avatar.png") == OK:
			img.resize(size, size, Image.INTERPOLATE_LANCZOS)
			return ImageTexture.create_from_image(img)
	return _user_icon(color, size)


func _user_icon(color: Color, size: int) -> ImageTexture:
	var svg: String = Profile.SVG_ICON
	var hex := "#%02x%02x%02x" % [int(color.r * 255), int(color.g * 255), int(color.b * 255)]
	var colored := svg.replace("currentColor", hex)
	var img := Image.new()
	img.load_svg_from_buffer(colored.to_utf8_buffer())
	img.resize(size, size, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


func _start_local_pool(mode: String, standard: bool, pool: String) -> void:
	Global.game_mode = mode
	Global.net_role = "local"
	Global.load_slot = 0
	Global.standard_mode = standard
	Global.perk_pool = pool
	Global.change_scene_with_fade("res://scenes/game.tscn")


func _has_any_save() -> bool:
	for i in range(1, 4):
		if FileAccess.file_exists("user://savegame_%d.json" % i):
			return true
	return false


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(200, 52)
	b.add_theme_font_override("font", _font())
	b.add_theme_font_size_override("font_size", 22)
	Global.style_flat_button(b)
	return b


var _font_cache: Font


func _font() -> Font:
	if _font_cache == null:
		_font_cache = load("res://fonts/zpix.ttf")

	return _font_cache
