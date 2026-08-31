# 自定义对局规则选项面板(大厅聊天框上方按钮弹出, X 关闭, 自动保存)
extends Panel

const FloatingPanel := preload("res://scripts/floating_panel.gd")

const RULES_PATH := "user://rules.json"

# 默认规则
const DEFAULT_RULES := {
	"win_mode": "classic",     # classic经典 / occupy占领 / kills杀棋计数
	"kill_count": 2,           # 杀棋计数:达成次数胜
	"skill_count": 3,          # 技能数量:每位玩家抽取技能数(1-4,默认3)
	"reroll": false,           # 选牌重置:8选3时显示"重置"按钮,未选的重抽
	"king_down": "grey",       # 将帅被杀后: grey变灰保留 / destroy全摧毁 / inherit继承
	"promotion": "queen",      # 升变: queen兵到中心变后 / none无升变
}

var panel: FloatingPanel
var rules := {}
var _font_ref: Font
var _on_change: Callable

# 选项控件引用
var win_btns := {}       # key -> Button
var king_btns := {}
var promo_btns := {}
var kill_edit: SpinBox


func setup(font: Font, on_change: Callable) -> void:
	_font_ref = font
	_on_change = on_change
	load_rules()

	position = Vector2(340, 200)
	size = Vector2(620, 480)
	panel = FloatingPanel.new()
	panel.position = Vector2.ZERO
	panel.size = size
	panel.setup("自定义对局规则", font)
	add_child(panel)

	# 右上角 X 关闭按钮
	var close_btn := Button.new()
	close_btn.text = "✕"
	Global.style_flat_button(close_btn)
	# 放在折叠按钮(右侧)左侧,避免重叠
	close_btn.position = Vector2(size.x - 44 - 40, 4)
	close_btn.size = Vector2(34, 28)
	close_btn.add_theme_font_override("font", font)
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(func(): visible = false)
	panel.add_child(close_btn)

	# 内容放入滚动区(内容较长,超出时可滚动)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 38)
	scroll.size = Vector2(size.x - 20, size.y - 38)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)

	# 获胜方式(无序号)
	_add_title(content, "获胜方式", 0)
	win_btns = _add_radio_row(content, {
		"classic": "经典模式:被吃帅判负,活到最后者胜",
		"occupy": "占领模式:占据中心棋盘 5 个位置中的 3 个者胜",
		"kills": "杀棋计数:每杀一王计 1 次,先达指定次数者胜",
	}, rules.get("win_mode", "classic"), func(k: String): _set_win(k))

	# 杀棋次数(仅 wins 模式显示)
	_add_title(content, "达成杀棋次数", 0)
	kill_edit = SpinBox.new()
	kill_edit.min_value = 1
	kill_edit.max_value = 9
	kill_edit.value = rules.get("kill_count", 2)
	kill_edit.custom_minimum_size = Vector2(120, 36)
	kill_edit.add_theme_font_override("font", font)
	kill_edit.value_changed.connect(func(_v: float): _save())
	content.add_child(kill_edit)

	# 将帅被杀后

	# 将帅被杀后
	_add_title(content, "将帅被杀后(经典/占领模式)", 0)
	king_btns = _add_radio_row(content, {
		"grey": "该方其他棋子变灰,保留在棋盘",
		"destroy": "该方所有棋子同时被摧毁",
		"inherit": "棋子继承给杀棋方",
	}, rules.get("king_down", "grey"), func(k: String): rules["king_down"] = k; _save())

	# 升变
	_add_title(content, "升变", 0)
	promo_btns = _add_radio_row(content, {
		"queen": "任意兵走到正中心升变为后",
		"none": "无升变",
	}, rules.get("promotion", "queen"), func(k: String): rules["promotion"] = k; _save())

	# 技能数量(1-4)
	_add_title(content, "技能数量(每位玩家抽取数, 1-4)", 0)
	var sc := SpinBox.new()
	sc.min_value = 1
	sc.max_value = 4
	sc.value = int(rules.get("skill_count", 3))
	sc.custom_minimum_size = Vector2(120, 36)
	sc.add_theme_font_override("font", font)
	sc.value_changed.connect(func(_v: float): rules["skill_count"] = int(sc.value); _save())
	content.add_child(sc)

	# 选牌重置开关(默认关)
	var reroll_chk := CheckButton.new()
	reroll_chk.text = "选牌重置:8选3时未选技能可重抽(已选保留)"
	reroll_chk.button_pressed = bool(rules.get("reroll", false))
	reroll_chk.add_theme_font_override("font", font)
	reroll_chk.add_theme_font_size_override("font_size", 14)
	reroll_chk.toggled.connect(func(on: bool): rules["reroll"] = on; _save())
	content.add_child(reroll_chk)

	_save()


func _add_title(parent: Node, text: String, _y: int) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font_ref)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.9, 0.82, 0.65))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(0, 26)
	parent.add_child(l)


# 一组单选按钮(竖排,VBox 自动布局),返回 key->Button 字典
func _add_radio_row(parent: Node, opts: Dictionary, current: String, on_pick: Callable) -> Dictionary:
	var btns := {}
	for k in opts:
		var b := Button.new()
		b.text = str(opts[k])
		b.toggle_mode = true
		b.button_pressed = (k == current)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# 透明背景(去掉黑底),选中时金色文字高亮
		b.add_theme_stylebox_override("normal", _transparent_style(false))
		b.add_theme_stylebox_override("hover", _transparent_style(false))
		b.add_theme_stylebox_override("pressed", _transparent_style(true))
		b.add_theme_stylebox_override("focus", _transparent_style(false))
		b.add_theme_stylebox_override("hover_pressed", _transparent_style(true))
		b.add_theme_color_override("font_color", Color(0.85, 0.82, 0.78))
		b.add_theme_color_override("font_pressed_color", Color(1.0, 0.85, 0.3))
		b.add_theme_color_override("font_hover_color", Color(0.95, 0.9, 0.85))
		# 自动宽度(按文字),不撑满面板
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.custom_minimum_size = Vector2(0, 30)
		b.add_theme_font_override("font", _font_ref)
		b.add_theme_font_size_override("font_size", 13)
		var key: String = String(k)
		b.pressed.connect(func():
			_select_only(btns, key)
			on_pick.call(key)
		)
		parent.add_child(b)
		btns[k] = b
	return btns


# 透明背景样式(选中时左侧金色圆点标识)
func _transparent_style(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 20  # 文字右移(避开选中圆点)
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	if selected:
		sb.border_color = Color(1.0, 0.85, 0.3)
		sb.set_border_width_all(1)
	return sb


func _select_only(btns: Dictionary, key: String) -> void:
	for k in btns:
		btns[k].button_pressed = (k == key)


func _set_win(k: String) -> void:
	rules["win_mode"] = k
	_save()
	_update_kill_visible()


func _update_kill_visible() -> void:
	if kill_edit != null:
		kill_edit.visible = (rules.get("win_mode", "classic") == "kills")


func load_rules() -> void:
	rules = DEFAULT_RULES.duplicate(true)
	if FileAccess.file_exists(RULES_PATH):
		var f := FileAccess.open(RULES_PATH, FileAccess.READ)
		if f != null:
			var data: Variant = JSON.parse_string(f.get_as_text())
			if data is Dictionary:
				for k in DEFAULT_RULES:
					if data.has(k):
						rules[k] = data[k]
	Global.game_rules = rules


func _save() -> void:
	var f := FileAccess.open(RULES_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(rules))
	f.close()
	Global.game_rules = rules
	_update_kill_visible()
	if _on_change.is_valid():
		_on_change.call(rules)
