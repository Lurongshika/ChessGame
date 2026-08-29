# 聊天面板:可拖动/折叠(复用 FloatingPanel 交互),消息列表 + 输入框 + 发送
# 用法: setup(字体) → 添加到自己节点树;调用 add_message(谁, 文本) 显示本地消息
extends Panel

const FloatingPanel := preload("res://scripts/floating_panel.gd")

var panel: FloatingPanel
var msg_box: VBoxContainer
var msg_scroll: ScrollContainer
var input: LineEdit
var send_btn: Button
var _font_ref: Font
var _on_send: Callable

# on_send(text) 由外部处理网络发送
func setup(font: Font, on_send: Callable) -> void:
	_font_ref = font
	_on_send = on_send
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

	# 输入行
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 4)
	panel.content.add_child(input_row)
	input = LineEdit.new()
	input.placeholder_text = "输入消息..."
	input.add_theme_font_override("font", font)
	input.add_theme_font_size_override("font_size", 14)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(0, 32)
	input.text_submitted.connect(func(_t: String): _send())
	input_row.add_child(input)
	send_btn = Button.new()
	send_btn.text = "发送"
	Global.style_flat_button(send_btn)
	send_btn.add_theme_font_override("font", font)
	send_btn.add_theme_font_size_override("font_size", 14)
	send_btn.custom_minimum_size = Vector2(56, 32)
	send_btn.pressed.connect(_send)
	input_row.add_child(send_btn)


func _send() -> void:
	var text := input.text.strip_edges()
	if text.is_empty():
		return
	input.text = ""
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
