# 技能卡:塔罗牌样式(正位/逆位牌面),可点击(主动技能触发)
# 鼠标悬浮:卡牌朝鼠标方向 3D 偏转(shader)+ 放大,并在鼠标右下方显示技能信息 tooltip
# 选中态:金色脉动描边 shader 增强确认感
# 牌面:assets/Tarot_Original/8X/{编号}_{英文名}.png,逆位 = 同一张图垂直翻转
extends Panel

signal clicked(perk_id: String, side: int)

const Tarot := preload("res://scripts/tarot.gd")

const CARD3D := preload("res://shaders/card_3d.gdshader")
const MAX_TILT := 11.0        # 悬浮偏转最大角度(度,限制为原一半)
const IDLE_SWAY := 6.0        # 选牌界面所有卡牌基础倾斜摆动(度)
const IDLE_BOB := 5.0         # 选牌界面所有卡牌基础上下漂浮(像素)
const SEL_LIFT := 8.0         # 选中额外上浮(像素)
const FAN_ANGLE := 13.0       # 选牌界面两端卡牌外倾角度(度,中间为 0)

var perk_id := ""
var _side := -1
var selected := false
var idle_float := false       # 选牌界面:所有卡牌持续飘动(摆动+漂浮),选中再叠 shader
var _fan := 0.0               # 外倾角(度,按所在列位置设置:左端负、右端正、中间 0)
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
var _base_pos := Vector2.ZERO   # 初始槽位(悬浮/浮动以此为基准)
var _base_captured := false
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
	var t := Time.get_ticks_msec() / 1000.0
	_mat.set_shader_parameter("time", t)

	# 选牌界面:所有卡牌持续飘动(相位按卡牌索引错开,参考 balatro-feel)
	var ph := 0.0
	if idle_float:
		ph = float(get_index())

	# 目标旋转角
	var target_rx := 0.0
	var target_ry := 0.0
	var target_scale := 1.0
	if idle_float:
		target_rx = sin(t * 2.0 + ph) * IDLE_SWAY
		target_ry = cos(t * 2.0 + ph) * IDLE_SWAY
	if _hover:
		# 悬停:叠加朝鼠标倾斜(减小飘动),并放大
		var local := get_local_mouse_position()
		var z := size
		if z.x <= 0.0 or z.y <= 0.0:
			z = Vector2.ONE
		var frac: Vector2 = local / z
		var off := (frac - Vector2(0.5, 0.5)) * 2.0
		off.x = clampf(off.x, -1.0, 1.0)
		off.y = clampf(off.y, -1.0, 1.0)
		var reduce := 0.3 if idle_float else 1.0
		target_rx = off.y * MAX_TILT + (sin(t * 2.0 + ph) * IDLE_SWAY * reduce * 0.3)
		target_ry = -off.x * MAX_TILT + (cos(t * 2.0 + ph) * IDLE_SWAY * reduce * 0.3)
		target_scale = 1.12

	var k := minf(delta * 10.0, 1.0)
	_rot_x = lerpf(_rot_x, target_rx, k)
	_rot_y = lerpf(_rot_y, target_ry, k)
	_curr_scale = lerpf(_curr_scale, target_scale, k)
	_mat.set_shader_parameter("x_rot", _rot_x)
	_mat.set_shader_parameter("y_rot", _rot_y)

	pivot_offset = size / 2.0
	scale = Vector2(_curr_scale, _curr_scale)
	rotation_degrees = lerpf(rotation_degrees, _fan, k)  # 两端卡牌外倾(扇形展开)

	# 上下漂浮:选牌界面所有卡牌上飘摆动;选中额外上浮(初始槽位为基准)
	if not _base_captured and size != Vector2.ZERO:
		_base_pos = position
		_base_captured = true
	var target_y := _base_pos.y
	if idle_float:
		target_y = _base_pos.y + sin(t * 1.5 + ph) * IDLE_BOB
	if selected:
		target_y = _base_pos.y - SEL_LIFT + (sin(t * 1.5 + ph) * IDLE_BOB if idle_float else 0.0)
	position.y = lerpf(position.y, target_y, k)
	position.x = _base_pos.x


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


# 设置外倾角(度):左端传负、右端传正、中间传 0,形成扇形展开
func set_fan(deg: float) -> void:
	_fan = deg


# 对局状态:ready=充能完毕闪箔流光,disabled=审判禁用红色,passive=被动卡青色(3 种 shader)
func set_game_state(ready: bool, disabled: bool, passive: bool) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("ready", 1.0 if ready else 0.0)
	_mat.set_shader_parameter("disabled", 1.0 if disabled else 0.0)
	_mat.set_shader_parameter("passive", 1.0 if passive else 0.0)


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
