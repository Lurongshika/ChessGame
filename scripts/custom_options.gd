# 自定义对局规则选项面板(大厅聊天框上方按钮弹出, X 关闭, 自动保存)
extends Panel

const FloatingPanel := preload("res://scripts/floating_panel.gd")

const RULES_PATH := "user://rules.json"

# 默认规则
const DEFAULT_RULES := {
	"win_mode": "classic",     # classic经典 / occupy占领 / kills杀棋计数
	"kill_count": 2,           # 杀棋计数:达成次数胜
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

	position = Vector2(340, 300)
	size = Vector2(600, 400)
	panel = FloatingPanel.new()
	panel.position = Vector2.ZERO
	panel.size = size
	panel.setup("自定义对局规则", font)
	add_child(panel)

	# 右上角 X 关闭按钮
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.position = Vector2(size.x - 40, 4)
	close_btn.size = Vector2(34, 28)
	close_btn.add_theme_font_override("font", font)
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(func(): visible = false)
	panel.add_child(close_btn)

	# 获胜方式
	var y := 8
	_add_title(panel, "1. 获胜方式", y)
	y += 30
	win_btns = _add_radio_row(panel, y, {
		"classic": "经典模式:被吃帅判负,活到最后者胜",
		"occupy": "占领模式:占据中心棋盘 5 个位置中的 3 个者胜",
		"kills": "杀棋计数:每杀一王计 1 次,先达 __ 次者胜",
	}, rules.get("win_mode", "classic"), func(k: String): _set_win(k))
	y += 110

	# 杀棋次数(仅 kills 模式显示)
	_add_title(panel, "2. 杀棋次数(杀棋计数模式)", y)
	y += 30
	kill_edit = SpinBox.new()
	kill_edit.min_value = 1
	kill_edit.max_value = 9
	kill_edit.value = rules.get("kill_count", 2)
	kill_edit.position = Vector2(60, y)
	kill_edit.size = Vector2(120, 36)
	kill_edit.add_theme_font_override("font", font)
	kill_edit.value_changed.connect(func(_v: float): _save())
	panel.add_child(kill_edit)
	y += 56

	# 将帅被杀后
	_add_title(panel, "3. 将帅被杀后(经典/占领模式)", y)
	y += 30
	king_btns = _add_radio_row(panel, y, {
		"grey": "该方其他棋子变灰,保留在棋盘",
		"destroy": "该方所有棋子同时被摧毁",
		"inherit": "棋子继承给杀棋方",
	}, rules.get("king_down", "grey"), func(k: String): rules["king_down"] = k; _save())
	y += 110

	# 升变
	_add_title(panel, "4. 升变", y)
	y += 30
	promo_btns = _add_radio_row(panel, y, {
		"queen": "任意兵走到正中心升变为后",
		"none": "无升变",
	}, rules.get("promotion", "queen"), func(k: String): rules["promotion"] = k; _save())
	y += 60

	_save()


func _add_title(parent: Node, text: String, y: int) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font_ref)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.9, 0.82, 0.65))
	l.position = Vector2(16, y)
	l.size = Vector2(560, 26)
	parent.add_child(l)


# 一组单选按钮(竖排),返回 key->Button 字典
func _add_radio_row(parent: Node, y: int, opts: Dictionary, current: String, on_pick: Callable) -> Dictionary:
	var btns := {}
	var yy := y
	for k in opts:
		var b := Button.new()
		b.text = str(opts[k])
		b.toggle_mode = true
		b.button_pressed = (k == current)
		b.position = Vector2(30, yy)
		b.size = Vector2(540, 30)
		b.add_theme_font_override("font", _font_ref)
		b.add_theme_font_size_override("font_size", 13)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var key: String = String(k)
		b.pressed.connect(func():
			_select_only(btns, key)
			on_pick.call(key)
		)
		parent.add_child(b)
		btns[k] = b
		yy += 34
	return btns


func _select_only(btns: Dictionary, key: String) -> void:
	for k in btns:
		btns[k].button_pressed = (k == key)


func _set_win(k: String) -> void:
	rules["win_mode"] = k
	# 杀棋次数输入框仅 kills 模式可见
	if kill_edit != null:
		kill_edit.visible = (k == "kills")
	_save()


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
	if _on_change.is_valid():
		_on_change.call(rules)
