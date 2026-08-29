extends Control

const BgLayer := preload("res://scripts/bg_layer.gd")

func _ready() -> void:
	var bg := BgLayer.new()
	add_child(bg)

	var title := _label("局域网联机", 44, Color(0.95, 0.85, 0.6))
	title.position = Vector2(0, 40)
	title.size = Vector2(1280, 54)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var ip_label := _label("本机 IP: " + _local_ip(), 18, Color(0.85, 0.8, 0.75))
	ip_label.position = Vector2(0, 140)
	ip_label.size = Vector2(1280, 28)
	ip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(ip_label)

	# ---- 创建房间:端口输入 + 按钮 ----
	var host_label := _label("创建房间", 20, Color(0.9, 0.75, 0.5))
	host_label.position = Vector2(380, 235)
	host_label.size = Vector2(540, 30)
	add_child(host_label)

	var host_port_edit := _port_edit(Vector2(680, 232))
	add_child(host_port_edit)

	var btn_host := _button("创建", Vector2(800, 230))
	btn_host.pressed.connect(func(): _host(host_port_edit.text))
	add_child(btn_host)

	# ---- 加入房间:IP + 端口输入 + 按钮 ----
	var join_label := _label("加入房间", 20, Color(0.6, 0.7, 0.95))
	join_label.position = Vector2(380, 325)
	join_label.size = Vector2(540, 30)
	add_child(join_label)

	var ip_edit := LineEdit.new()
	ip_edit.placeholder_text = "对方 IP/域名,如 192.168.1.23"
	ip_edit.position = Vector2(390, 365)
	ip_edit.size = Vector2(250, 40)
	ip_edit.add_theme_font_override("font", _font())
	ip_edit.add_theme_font_size_override("font_size", 17)
	add_child(ip_edit)

	var join_port_edit := _port_edit(Vector2(650, 362))
	add_child(join_port_edit)

	var btn_join := _button("加入", Vector2(760, 360))
	btn_join.pressed.connect(func(): _join(ip_edit.text, join_port_edit.text))
	add_child(btn_join)

	var btn_back := _button("返回", Vector2(540, 500))
	btn_back.pressed.connect(func(): Global.change_scene_with_fade("res://scenes/main.tscn"))
	add_child(btn_back)
	Global.animate_ui_in(self)


func _port_edit(pos: Vector2) -> LineEdit:
	var e := LineEdit.new()
	e.text = str(Global.port)
	e.placeholder_text = "端口"
	e.position = pos
	e.size = Vector2(100, 40)
	e.add_theme_font_override("font", _font())
	e.add_theme_font_size_override("font_size", 17)
	return e


func _host(port_text: String) -> void:
	Global.port = _parse_port(port_text, Global.port)
	Global.net_role = "host"
	Global.change_scene_with_fade("res://scenes/game.tscn")


func _join(ip: String, port_text: String) -> void:
	if ip.strip_edges().is_empty():
		return
	Global.port = _parse_port(port_text, Global.port)
	Global.net_role = "client"
	Global.server_ip = ip.strip_edges()
	Global.change_scene_with_fade("res://scenes/game.tscn")


func _parse_port(text: String, fallback: int) -> int:
	var p := int(text.strip_edges())
	if p > 0 and p <= 65535:
		return p
	return fallback


func _local_ip() -> String:
	for addr in IP.get_local_addresses():
		if addr.begins_with("127.") or addr.contains(":"):
			continue
		return addr
	return "未知"


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(130, 52)
	b.add_theme_font_override("font", _font())
	b.add_theme_font_size_override("font_size", 20)
	Global.style_flat_button(b)
	return b


var _font_cache: Font


func _font() -> Font:
	if _font_cache == null:
		_font_cache = load("res://fonts/zpix.ttf")

	return _font_cache
