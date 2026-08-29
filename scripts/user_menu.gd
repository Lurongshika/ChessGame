extends Control

const BgLayer := preload("res://scripts/bg_layer.gd")
const Profile := preload("res://scripts/profile_util.gd")

const PROFILE_PATH := "user://profile.json"

# 颜色偏好:从 Global.COLORS16(12 色)中选,最多 4 个
const MAX_PREFS := 4

var color_prefs: Array = []   # COLORS16 索引,最多 4 个
var custom_avatar := false
var username_edit: LineEdit
var pref_btns: Array = []      # 12 色按钮
var pref_dots: Array = []      # 每个色按钮右上角的小标记(显示是否已选)
var avatar_preview: TextureRect
var file_dialog: FileDialog


func _ready() -> void:
	var bg := BgLayer.new()
	add_child(bg)

	var title := _label("用户设置", 40, Color(0.95, 0.85, 0.6))
	title.position = Vector2(0, 60)
	title.size = Vector2(1280, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	# 左侧:头像区(无预设颜色头像,仅自定义上传)
	var avatar_title := _label("我的头像", 20, Color(0.9, 0.8, 0.6))
	avatar_title.position = Vector2(140, 180)
	avatar_title.size = Vector2(160, 30)
	add_child(avatar_title)

	avatar_preview = TextureRect.new()
	avatar_preview.position = Vector2(150, 220)
	avatar_preview.size = Vector2(160, 160)
	avatar_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 头像框
	var frame := Panel.new()
	frame.position = Vector2(142, 212)
	frame.size = Vector2(176, 176)
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.14, 0.16, 0.2, 0.6)
	fsb.set_corner_radius_all(12)
	fsb.border_color = Color(0.5, 0.45, 0.35)
	fsb.set_border_width_all(2)
	frame.add_theme_stylebox_override("panel", fsb)
	add_child(frame)

	var upload_btn := _button("上传头像", Vector2(150, 400), Vector2(160, 46))
	upload_btn.pressed.connect(_open_upload)
	add_child(upload_btn)

	var upload_tip := _label("支持 PNG/JPG/WebP", 13, Color(0.6, 0.58, 0.54))
	upload_tip.position = Vector2(150, 452)
	upload_tip.size = Vector2(180, 20)
	add_child(upload_tip)

	# 右侧:颜色偏好(最多 4 个,点击切换选中;12 色 3×4 排列)
	var pref_title := _label("颜色偏好(最多 %d 个,开局按此选色)" % MAX_PREFS, 20, Color(0.9, 0.8, 0.6))
	pref_title.position = Vector2(480, 180)
	pref_title.size = Vector2(560, 30)
	add_child(pref_title)

	for i in Global.COLORS16.size():
		var btn := Button.new()
		btn.position = Vector2(480 + (i % 4) * 130, 225 + (i / 4) * 100)
		btn.size = Vector2(110, 84)
		btn.icon = _color_swatch(Global.COLORS16[i], 56)
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var idx := i
		btn.pressed.connect(func(): _toggle_pref(idx))
		add_child(btn)
		pref_btns.append(btn)
		# 序号标记(显示偏好顺序)
		var dot := _label("", 14, Color(0.95, 0.85, 0.6))
		dot.position = btn.position + Vector2(84, 2)
		dot.size = Vector2(24, 22)
		dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(dot)
		pref_dots.append(dot)

	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; 图片"])
	file_dialog.file_selected.connect(_on_file_selected)
	add_child(file_dialog)

	var name_tip := _label("用户名", 18, Color(0.8, 0.75, 0.7))
	name_tip.position = Vector2(430, 450)
	name_tip.size = Vector2(100, 28)
	add_child(name_tip)

	username_edit = LineEdit.new()
	username_edit.placeholder_text = "输入用户名"
	username_edit.position = Vector2(530, 448)
	username_edit.size = Vector2(320, 40)
	username_edit.add_theme_font_override("font", _font())
	username_edit.add_theme_font_size_override("font_size", 18)
	add_child(username_edit)

	var save_btn := _button("保存", Vector2(540, 530), Vector2(200, 52))
	save_btn.pressed.connect(_save)
	add_child(save_btn)

	var back_btn := _button("返回", Vector2(540, 600), Vector2(200, 52))
	back_btn.pressed.connect(func(): Global.change_scene_with_fade("res://scenes/main.tscn"))
	add_child(back_btn)

	_load_profile()
	Global.animate_ui_in(self)


# 点击颜色:切换是否加入偏好(最多 4 个)
func _toggle_pref(idx: int) -> void:
	if idx in color_prefs:
		color_prefs.erase(idx)
	else:
		if color_prefs.size() >= MAX_PREFS:
			# 替换最后一个
			color_prefs.pop_back()
		color_prefs.append(idx)
	_refresh_pref_highlight()
	_refresh_avatar_preview()


func _open_upload() -> void:
	file_dialog.popup_centered(Vector2i(640, 440))


func _on_file_selected(path: String) -> void:
	var img := Image.new()
	if img.load(path) != OK:
		return
	img.resize(128, 128, Image.INTERPOLATE_LANCZOS)
	img.save_png("user://avatar.png")
	custom_avatar = true
	_refresh_avatar_preview()


func _refresh_avatar_preview() -> void:
	if avatar_preview == null:
		return
	if custom_avatar and FileAccess.file_exists("user://avatar.png"):
		var img := Image.new()
		img.load("user://avatar.png")
		avatar_preview.texture = ImageTexture.create_from_image(img)
	elif not color_prefs.is_empty():
		# 无自定义头像:显示第一个偏好色块
		avatar_preview.texture = _color_swatch(Global.COLORS16[color_prefs[0]], 128)
	else:
		avatar_preview.texture = null


# 刷新颜色按钮高亮 + 偏好顺序数字
func _refresh_pref_highlight() -> void:
	for i in pref_btns.size():
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.2, 0.19, 0.17)
		sb.set_corner_radius_all(8)
		var order := color_prefs.find(i)
		if order >= 0:
			sb.border_color = Color(0.95, 0.8, 0.2)
			sb.set_border_width_all(3)
		else:
			sb.border_color = Color(0.4, 0.37, 0.32)
			sb.set_border_width_all(1)
		pref_btns[i].add_theme_stylebox_override("normal", sb)
		pref_btns[i].add_theme_stylebox_override("hover", sb)
		pref_btns[i].add_theme_stylebox_override("pressed", sb)
		pref_dots[i].text = str(order + 1) if order >= 0 else ""


func _save() -> void:
	var name_text := username_edit.text.strip_edges()
	if name_text.is_empty():
		name_text = "玩家"
	var data := {"username": name_text, "color_prefs": color_prefs, "custom_avatar": custom_avatar}
	var f := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	# 保存后返回主菜单
	Global.change_scene_with_fade("res://scenes/main.tscn")


func _load_profile() -> void:
	if not FileAccess.file_exists(PROFILE_PATH):
		_refresh_pref_highlight()
		_refresh_avatar_preview()
		return
	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data == null:
		_refresh_pref_highlight()
		_refresh_avatar_preview()
		return
	username_edit.text = data.get("username", "")
	custom_avatar = bool(data.get("custom_avatar", false))
	color_prefs = []
	for v in data.get("color_prefs", []):
		var ci := int(v)
		if ci >= 0 and ci < Global.COLORS16.size() and not ci in color_prefs:
			color_prefs.append(ci)
			if color_prefs.size() >= MAX_PREFS:
				break
	_refresh_pref_highlight()
	_refresh_avatar_preview()


func _color_swatch(color: Color, size: int) -> ImageTexture:
	# 纯色圆块(颜色偏好选择用)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size / 2.0, size / 2.0)
	for y in size:
		for x in size:
			var alpha := 1.0 if Vector2(x, y).distance_to(c) <= size / 2.0 - 1 else 0.0
			img.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))
	return ImageTexture.create_from_image(img)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, pos: Vector2, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.add_theme_font_override("font", _font())
	b.add_theme_font_size_override("font_size", 20)
	Global.style_flat_button(b)
	return b


var _font_cache: Font


func _font() -> Font:
	if _font_cache == null:
		_font_cache = load("res://fonts/zpix.ttf")
	return _font_cache
