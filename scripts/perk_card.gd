# 技能卡:塔罗牌样式(正位/逆位牌面),可点击(主动技能触发)
# 鼠标悬浮:卡牌朝鼠标方向 3D 偏转(shader)+ 放大,并在鼠标右下方显示技能信息 tooltip
# 选中态:金色脉动描边 shader 增强确认感
# 牌面:assets/Tarot_Original/8X/{编号}_{英文名}.png,逆位 = 同一张图垂直翻转
extends Panel

signal clicked(perk_id: String, side: int)

const Tarot := preload("res://scripts/tarot.gd")

const CARD3D := preload("res://shaders/card_3d.gdshader")
const MAX_TILT := 22.0  # 悬浮偏转最大角度(度)

var perk_id := ""
var _side := -1
var selected := false
var bg_tint := Color(-1, -1, -1)  # 自定义边框色(四人模式玩家色,-1 表示用默认)
var _tooltip: Control              # 共享悬浮提示(可空)
var _title := ""
var _tip_text := ""
var _desc := ""
var _font: Font

var _mat: ShaderMaterial
var _tex: TextureRect
var _hover := false
var _rot_x := 0.0
var _rot_y := 0.0
var _curr_scale := 1.0


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

	# 3D 偏转 shader 应用到牌面
	_mat = ShaderMaterial.new()
	_mat.shader = CARD3D
	_mat.set_shader_parameter("rect_size", size)
	_mat.set_shader_parameter("x_rot", 0.0)
	_mat.set_shader_parameter("y_rot", 0.0)
	_mat.set_shader_parameter("selected", 1.0 if selected else 0.0)
	_mat.set_shader_parameter("time", 0.0)

	# 牌面(铺满矩形,按比例居中)
	_tex = TextureRect.new()
	_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex.texture = Tarot.texture(id)  # 逆位已烘焙翻转
	_tex.material = _mat
	add_child(_tex)

	_refresh_style(is_self, card_w)
	set_process(true)


# 逐帧驱动 3D 偏转/放大/脉动
func _process(delta: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("rect_size", size)
	_mat.set_shader_parameter("time", Time.get_ticks_msec() / 1000.0)

	# 悬停:按鼠标相对卡牌中心偏移计算目标旋转角(朝鼠标方向偏转)
	var target_rx := 0.0
	var target_ry := 0.0
	var target_scale := 1.0
	if _hover:
		var local := get_local_mouse_position()
		var z := size
		if z.x <= 0.0 or z.y <= 0.0:
			z = Vector2.ONE
		var frac: Vector2 = local / z
		var off := (frac - Vector2(0.5, 0.5)) * 2.0
		target_rx = off.y * MAX_TILT
		target_ry = -off.x * MAX_TILT
		target_scale = 1.12

	var k := minf(delta * 10.0, 1.0)
	_rot_x = lerpf(_rot_x, target_rx, k)
	_rot_y = lerpf(_rot_y, target_ry, k)
	_curr_scale = lerpf(_curr_scale, target_scale, k)
	_mat.set_shader_parameter("x_rot", _rot_x)
	_mat.set_shader_parameter("y_rot", _rot_y)

	pivot_offset = size / 2.0
	scale = Vector2(_curr_scale, _curr_scale)


# 鼠标悬浮:3D 偏转 + 显示技能信息
func _on_hover_enter() -> void:
	_hover = true
	if _tooltip != null and _tooltip.has_method("show_for"):
		_tooltip.show_for(perk_id, _title, _tip_text, _desc)


func _on_hover_exit() -> void:
	_hover = false
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


# 选中态:金色脉动描边 shader 增强确认感(图鉴/选卡界面用)
func set_selected(v: bool) -> void:
	selected = v
	if _mat != null:
		_mat.set_shader_parameter("selected", 1.0 if v else 0.0)
	_refresh_style(true, 0.0)


# 边框样式:bg_tint 玩家色;默认深色底 + 细边框(选中态由 shader 描边表现)
func _refresh_style(is_self: bool, card_w: float = 0.0) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.09, 0.13, 0.95)
	if bg_tint.r >= 0.0:
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
