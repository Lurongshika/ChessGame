# 技能卡:塔罗牌样式(正位/逆位牌面),可点击(主动技能触发)
# 鼠标悬浮时在鼠标右下方显示技能信息 tooltip
# 牌面:assets/Tarot_Original/8X/{编号}_{英文名}.png,逆位 = 同一张图垂直翻转
extends Panel

signal clicked(perk_id: String, side: int)

const Tarot := preload("res://scripts/tarot.gd")

var perk_id := ""
var _side := -1
var selected := false
var bg_tint := Color(-1, -1, -1)  # 自定义边框色(四人模式玩家色,-1 表示用默认)
var _tooltip: Control              # 共享悬浮提示(可空)
var _title := ""
var _tip_text := ""
var _desc := ""
var _font: Font


func setup(id: String, side_id: int, title: String, tip: String, desc: String, font: Font, is_self: bool, card_w: float, tooltip: Control = null) -> void:
	perk_id = id
	_side = side_id
	_title = title
	_tip_text = tip
	_desc = desc
	_font = font
	_tooltip = tooltip

	# 默认按牌面比例;调用方可再设置 size(牌图保持比例居中,不变形)
	custom_minimum_size = Tarot.card_size(card_w)

	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_hover_enter)
	mouse_exited.connect(_on_hover_exit)

	# 牌面(铺满矩形,按比例居中)
	var tex := TextureRect.new()
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.texture = Tarot.texture(id)
	tex.flip_v = Tarot.is_reversed(id)
	add_child(tex)

	# 牌面底部:中文技能名(半透明黑条)
	var n := Label.new()
	n.text = title
	n.add_theme_font_override("font", font)
	n.add_theme_font_size_override("font_size", 12)
	n.add_theme_color_override("font_color", Color(1, 0.95, 0.82))
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	n.position = Vector2(0, -18)
	n.size = Vector2(size.x, 18)
	n.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_KEEP_SIZE)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nb := StyleBoxFlat.new()
	nb.bg_color = Color(0, 0, 0, 0.55)
	n.add_theme_stylebox_override("normal", nb)
	add_child(n)

	_refresh_style(is_self, card_w)


# 鼠标悬浮:在共享 tooltip 显示技能信息
func _on_hover_enter() -> void:
	if _tooltip != null and _tooltip.has_method("show_for"):
		_tooltip.show_for(perk_id, _title, _tip_text, _desc)


func _on_hover_exit() -> void:
	if _tooltip != null and _tooltip.has_method("hide_tip"):
		_tooltip.hide_tip()


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


# 选中态(图鉴/选卡界面用)
func set_selected(v: bool) -> void:
	selected = v
	_refresh_style(true, 0.0)


# 边框样式:选中金色;bg_tint 玩家色;默认深色底 + 细边框
func _refresh_style(is_self: bool, card_w: float = 0.0) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.09, 0.13, 0.95)
	if selected:
		bg.bg_color = Color(0.12, 0.1, 0.06, 0.97)
		bg.border_color = Color(1.0, 0.85, 0.3)
		bg.set_border_width_all(3)
	elif bg_tint.r >= 0.0:
		bg.border_color = bg_tint
		bg.set_border_width_all(2)
	elif is_self:
		bg.border_color = Color(0.55, 0.68, 0.85)
		bg.set_border_width_all(1)
	else:
		bg.border_color = Color(0.85, 0.55, 0.45)
		bg.set_border_width_all(1)
	bg.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", bg)
	queue_redraw()
