# 聊天面板:可拖动/折叠(复用 FloatingPanel 交互),消息列表 + 输入框 + 发送
# 用法: setup(字体, on_send) → 添加到自己节点树;调用 add_message(谁, 文本) 显示本地消息
# on_tab(text) 由外部处理 Tab 自动补全,返回 {text: 补全后文本, hint: 提示列表} 或 null
extends Panel

const FloatingPanel := preload("res://scripts/floating_panel.gd")

var panel: FloatingPanel
var msg_box: VBoxContainer
var msg_scroll: ScrollContainer
var input: LineEdit
var send_btn: Button
var hint_label: Label
var _font_ref: Font
var _on_send: Callable
var _on_tab: Callable
var _tab_candidates: Array = []  # 当前候选列表(循环补全)
var _tab_index := -1
var _tab_base := ""              # 进入候选时的原始输入
var _program_set := false         # 程序填入文本时跳过 text_changed 清理

# on_send(text) 由外部处理网络发送;on_tab(text) 由外部处理 Tab 补全(可空)
func setup(font: Font, on_send: Callable, on_tab: Callable = Callable()) -> void:
	_font_ref = font
	_on_send = on_send
	_on_tab = on_tab
	position = Vector2(20, 720 - 40 - 240)
	size = Vector2(300, 240)
	panel = FloatingPanel.new()
	panel.position = Vector2.ZERO
	panel.size = size
	panel.setup("聊天", font)
	add_child(panel)

	# 消息滚动区
	msg_scroll = ScrollContainer.new()
	msg_scroll.custom_minimum_size = Vector2(0, 0)
	msg_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	msg_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.content.add_child(msg_scroll)
	msg_box = VBoxContainer.new()
	msg_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_box.add_theme_constant_override("separation", 3)
	msg_scroll.add_child(msg_box)

	# 补全提示行(小字,显示当前候选)
	hint_label = Label.new()
	hint_label.add_theme_font_override("font", font)
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	hint_label.text = ""
	panel.content.add_child(hint_label)

	# 输入行
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 4)
	panel.content.add_child(input_row)
	input = LineEdit.new()
	input.placeholder_text = "输入消息...(Tab 补全指令)"
	input.add_theme_font_override("font", font)
	input.add_theme_font_size_override("font_size", 14)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(0, 32)
	input.text_submitted.connect(func(_t: String): _send())
	input.text_changed.connect(_on_text_changed)
	input.gui_input.connect(_on_input)
	input_row.add_child(input)
	send_btn = Button.new()
	send_btn.text = "发送"
	Global.style_flat_button(send_btn)
	send_btn.add_theme_font_override("font", font)
	send_btn.add_theme_font_size_override("font_size", 14)
	send_btn.custom_minimum_size = Vector2(56, 32)
	send_btn.pressed.connect(_send)
	input_row.add_child(send_btn)


# 输入框按键:Tab 触发补全
func _on_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_tab_complete()
		input.accept_event()


func _tab_complete() -> void:
	if not _on_tab.is_valid():
		return
	var cur := input.text
	# 有候选集:若当前输入是原始输入 → 填入候选[0];若是当前候选 → 循环下一个
	if _tab_candidates.size() > 0:
		if cur == _tab_base:
			_tab_index = 0
			_set_input_text(_tab_candidates[0])
			_set_hint(_tab_candidates)
			return
		if _tab_index >= 0 and cur == _tab_candidates[_tab_index]:
			_tab_index = (_tab_index + 1) % _tab_candidates.size()
			_set_input_text(_tab_candidates[_tab_index])
			_set_hint(_tab_candidates)
			return
	var result = _on_tab.call(cur)
	_tab_candidates = []
	_tab_index = -1
	_tab_base = cur
	if result is Dictionary and result.has("text"):
		var new_text := String(result["text"])
		if new_text != cur:
			_set_input_text(new_text)
	# 多个候选:记录以便循环补全(候选文本从 hint 数组取)
	var hint_val = result.get("hint", "") if result is Dictionary else ""
	if hint_val is Array and hint_val.size() > 1:
		_tab_candidates = hint_val.duplicate()
		_tab_index = -1
		_set_hint(_tab_candidates)
	else:
		_set_hint(hint_val)


func _on_text_changed(_t: String) -> void:
	# 用户手动编辑时清空候选;程序填入(补全)时保留候选以支持循环
	if not _program_set:
		_tab_candidates = []
		_tab_index = -1


func _set_input_text(text: String) -> void:
	_program_set = true
	input.text = text
	input.caret_column = text.length()
	_program_set = false


func _set_hint(hint) -> void:
	if hint_label == null:
		return
	if hint is Array and hint.is_empty():
		hint_label.text = ""
	elif hint is String and hint.is_empty():
		hint_label.text = ""
	elif hint is Array:
		hint_label.text = "提示(Tab循环): " + "、 ".join(hint)
	else:
		hint_label.text = "提示: " + str(hint)


func _send() -> void:
	var text := input.text.strip_edges()
	if text.is_empty():
		return
	input.text = ""
	_set_hint("")
	if _on_send.is_valid():
		_on_send.call(text)


# 显示一条消息(谁 + 文本)
func add_message(who: String, text: String) -> void:
	print("CHAT: ", who, ": ", text)
	var l := Label.new()
	l.text = ("%s: %s" % [who, text]) if who != "" else text
	l.add_theme_font_override("font", _font_ref)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_box.add_child(l)
	# 滚动到底部
	await get_tree().process_frame
	if msg_scroll != null:
		msg_scroll.scroll_vertical = 100000
