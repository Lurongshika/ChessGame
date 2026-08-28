# 技能卡:圆角矩形卡片,名字/tip/描述三部分,可点击(主动技能触发)
extends Panel

signal clicked(perk_id: String, side: int)

var perk_id := ""
var _side := -1
var selected := false
var bg_tint := Color(-1, -1, -1)  # 自定义背景色(-1 表示用默认)


func setup(id: String, side_id: int, title: String, tip: String, desc: String, font: Font, is_self: bool, card_w: float) -> void:
	perk_id = id
	_side = side_id
	_refresh_style(is_self, card_w)
	# 描述每 18 字换行,卡片高度自适应
	var wrapped_desc := ""
	var ch_count := 0
	for ch in desc:
		wrapped_desc += ch
		ch_count += 1
		if ch_count >= 18:
			wrapped_desc += "\n"
			ch_count = 0
	var desc_lines := maxi(1, ceili(desc.length() / 18.0))
	var card_h := 41 + desc_lines * 15 + 6
	custom_minimum_size = Vector2(card_w, card_h)

	mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh_style(is_self, card_w)

	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", font)
	t.add_theme_font_size_override("font_size", 15)
	t.add_theme_color_override("font_color", Color(1, 0.93, 0.75))
	t.position = Vector2(10, 4)
	t.size = Vector2(card_w - 20, 20)
	add_child(t)

	var tp := Label.new()
	tp.text = tip
	tp.add_theme_font_override("font", font)
	tp.add_theme_font_size_override("font_size", 11)
	tp.add_theme_color_override("font_color", Color(0.62, 0.82, 1.0) if is_self else Color(1.0, 0.7, 0.6))
	tp.position = Vector2(10, 24)
	tp.size = Vector2(card_w - 20, 15)
	add_child(tp)

	var d := Label.new()
	d.text = wrapped_desc
	d.add_theme_font_override("font", font)
	d.add_theme_font_size_override("font_size", 11)
	d.add_theme_color_override("font_color", Color(0.85, 0.82, 0.78))
	d.position = Vector2(10, 41)
	d.size = Vector2(card_w - 20, desc_lines * 15)
	d.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(d)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 点击技能卡:所在悬浮窗置顶
		_raise_panel()
		clicked.emit(perk_id, _side)
		accept_event()


# 向上找最近的悬浮窗(FloatingPanel)并置顶
func _raise_panel() -> void:
	var node := get_parent()
	while node != null:
		if node.has_method("toggle_collapse"):
			var parent := node.get_parent()
			if parent != null:
				parent.remove_child(node)
				parent.add_child(node)
			return
		node = node.get_parent()


func _refresh_style(is_self: bool, card_w: float) -> void:
	# 圆角矩形样式(己方偏蓝,敌方偏红;选中金色高亮)
	var bg := StyleBoxFlat.new()
	if selected:
		bg.bg_color = Color(0.35, 0.28, 0.12, 0.97)
		bg.border_color = Color(1.0, 0.85, 0.3)
		bg.set_border_width_all(3)
	else:
		if bg_tint.r >= 0.0:
			# 自定义背景色(四人模式玩家色)
			bg.bg_color = Color(bg_tint.r * 0.55 + 0.15, bg_tint.g * 0.55 + 0.12, bg_tint.b * 0.55 + 0.12, 0.95)
			bg.border_color = bg_tint
		elif is_self:
			bg.bg_color = Color(0.18, 0.28, 0.4, 0.95)
			bg.border_color = Color(0.55, 0.68, 0.85)
		else:
			bg.bg_color = Color(0.38, 0.24, 0.2, 0.92)
			bg.border_color = Color(0.85, 0.55, 0.45)
		bg.set_border_width_all(1)
	bg.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", bg)
	queue_redraw()
