# 可拖动/折叠/缩放的浮动面板(交互与系统应用窗口一致)
# - 按住标题栏拖动移动
# - 标题栏右侧按钮折叠/展开
# - 拖拽右下角缩放
extends Panel

const TITLE_H := 34
const HANDLE := 16
const DEFAULT_EXPANDED_Y := 420

var panel_title: Label
var collapse_btn: Button
var content: VBoxContainer
var collapsed := false

var _title_bar: Control
var _font_ref: Font
var _dragging := false
var _drag_container: CanvasItem = self
var _resizing := false
var _grab := Vector2.ZERO
var _orig_pos := Vector2.ZERO
var _expanded_size := Vector2(230, DEFAULT_EXPANDED_Y)


func setup(title: String, font: Font) -> void:
	_font_ref = font
	# 外部应先设置好 position/size 再调用 setup
	_expanded_size = Vector2(maxf(size.x, 160), maxf(size.y, TITLE_H + 60))
	# 弹入动画:elastic 回弹(参考 godot-tween-cheatsheet)
	Global.pop_in(self)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 显式背景样式(固定颜色,折叠/展开不变化)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.16, 0.18, 0.24, 0.55)
	bg.set_corner_radius_all(6)
	bg.border_color = Color(0.45, 0.4, 0.32)
	bg.set_border_width_all(2)
	bg.content_margin_left = 0
	bg.content_margin_right = 0
	bg.content_margin_top = 0
	bg.content_margin_bottom = 0
	add_theme_stylebox_override("panel", bg)

	# 标题栏(拖动区域)
	_title_bar = Control.new()
	_title_bar.position = Vector2.ZERO
	_title_bar.size = Vector2(size.x, TITLE_H)
	_drag_container = _find_drag_container()
	# IGNORE:标题栏区域事件直接由面板接收(折叠按钮由 Button 自己处理),确保拖动可靠
	_title_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_bar)

	panel_title = Label.new()
	panel_title.text = title
	panel_title.add_theme_font_override("font", _font_ref)
	panel_title.add_theme_font_size_override("font_size", 18)
	panel_title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
	panel_title.position = Vector2(10, 6)
	panel_title.size = Vector2(size.x - 60, TITLE_H - 8)
	_title_bar.add_child(panel_title)

	collapse_btn = Button.new()
	collapse_btn.text = "—"
	Global.style_flat_button(collapse_btn)
	collapse_btn.position = Vector2(size.x - 44, 4)
	collapse_btn.size = Vector2(38, TITLE_H - 8)
	collapse_btn.add_theme_font_override("font", _font_ref)
	collapse_btn.add_theme_font_size_override("font_size", 16)
	collapse_btn.pressed.connect(toggle_collapse)
	_title_bar.add_child(collapse_btn)

	# 内容区
	content = VBoxContainer.new()
	content.position = Vector2(10, TITLE_H + 8)
	content.size = Vector2(size.x - 20, size.y - TITLE_H - 18)
	content.add_theme_constant_override("separation", 6)
	add_child(content)


func toggle_collapse() -> void:
	collapsed = not collapsed
	content.visible = not collapsed
	collapse_btn.text = "+" if collapsed else "—"
	if collapsed:
		size.y = TITLE_H + 8
	else:
		size.y = maxf(_expanded_size.y, TITLE_H + 60)
	_update_layout()


func _update_layout() -> void:
	_title_bar.size = Vector2(size.x, TITLE_H)
	panel_title.size = Vector2(size.x - 60, TITLE_H - 8)
	collapse_btn.position = Vector2(size.x - 44, 4)
	content.size = Vector2(size.x - 20, maxf(0, size.y - TITLE_H - 18))


# 找到拖拽时应移动的最外层容器(父链上最外层 Panel;若父是 CanvasLayer/根则移动自己)
func _find_drag_container() -> CanvasItem:
	var node: CanvasItem = self
	while node.get_parent() != null and node.get_parent() is Panel:
		node = node.get_parent()
	return node


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# 点击时置顶:提高 z_index(不移动节点,避免打断拖拽事件流)
		if event.pressed:
			_raise_top()
		var lp: Vector2 = event.position
		if event.pressed:
			_drag_container = _find_drag_container()
			_dragging = lp.y <= TITLE_H and not _point_in(lp, collapse_btn.get_rect())
			_resizing = lp.x >= size.x - HANDLE and lp.y >= size.y - HANDLE
			_grab = lp
			_orig_pos = _drag_container.position
			# 折叠状态下按下不更新展开尺寸(避免污染)
			if not collapsed:
				_expanded_size = size
		else:
			_dragging = false
			_resizing = false
		accept_event()
	elif event is InputEventMouseMotion and (_dragging or _resizing):
		var delta: Vector2 = event.position - _grab
		if _dragging:
			var p: Vector2 = _orig_pos + delta
			var vp: Vector2 = get_viewport_rect().size
			p.x = clampf(p.x, 0, maxf(0, vp.x - _drag_container.size.x))
			p.y = clampf(p.y, 0, maxf(0, vp.y - _drag_container.size.y))
			_drag_container.position = p
		if _resizing:
			var s: Vector2 = _expanded_size + delta
			s.x = maxf(s.x, 160)
			s.y = maxf(s.y, TITLE_H + 50)
			size = s
			_expanded_size = s
			_update_layout()
		accept_event()


# 点击置顶:把整个悬浮窗容器(最外层 Panel)提到同父级最上,不修改节点树
func _raise_top() -> void:
	# 找到最外层容器(父不是 Panel 的 Panel)
	var container: CanvasItem = self
	while container.get_parent() != null and container.get_parent() is Panel:
		container = container.get_parent()
	var parent = container.get_parent()
	if parent == null:
		return
	var max_z := 0
	for child in parent.get_children():
		if child is CanvasItem:
			max_z = maxi(max_z, (child as CanvasItem).z_index)
	container.z_index = max_z + 1


func _point_in(p: Vector2, rect: Rect2) -> bool:
	return p.x >= rect.position.x and p.x <= rect.position.x + rect.size.x \
		and p.y >= rect.position.y and p.y <= rect.position.y + rect.size.y
