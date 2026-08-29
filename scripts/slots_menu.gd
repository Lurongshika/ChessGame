extends Control

const BgLayer := preload("res://scripts/bg_layer.gd")

const SLOT_COUNT := 3
var back_btn: Button


func _ready() -> void:
	var bg := BgLayer.new()
	add_child(bg)

	var title := _label("选择存档", 44, Color(0.95, 0.85, 0.6))
	title.position = Vector2(0, 60)
	title.size = Vector2(1280, 54)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	_build_slots()

	back_btn = _button("返回", Vector2(540, 500), Vector2(200, 52))
	back_btn.pressed.connect(func(): Global.change_scene_with_fade("res://scenes/main.tscn"))
	add_child(back_btn)


func _build_slots() -> void:
	for i in range(1, SLOT_COUNT + 1):
		var has := FileAccess.file_exists(_path(i))
		var info := _slot_info(i) if has else "空"
		var btn := _button("存档 %d — %s" % [i, info], Vector2(460, 180 + (i - 1) * 90), Vector2(360, 60))
		var slot := i
		btn.pressed.connect(func(): _load_slot(slot))
		btn.disabled = not has
		add_child(btn)
		if has:
			# 删除按钮(X)
			var del := _button("✕", Vector2(840, 180 + (i - 1) * 90), Vector2(50, 60))
			del.pressed.connect(func(): _delete_slot(slot))
			add_child(del)


func _path(slot: int) -> String:
	return "user://savegame_%d.json" % slot


func _load_slot(slot: int) -> void:
	Global.net_role = "local"
	Global.load_slot = slot
	Global.change_scene_with_fade("res://scenes/game.tscn")


func _delete_slot(slot: int) -> void:
	var p := ProjectSettings.globalize_path(_path(slot))
	if FileAccess.file_exists(_path(slot)):
		DirAccess.remove_absolute(p)
	# 重建槽列表(保留返回按钮)
	for child in get_children():
		if child is Button and child != back_btn:
			child.queue_free()
	_build_slots()


func _slot_info(slot: int) -> String:
	var f := FileAccess.open(_path(slot), FileAccess.READ)
	if f == null:
		return "空"
	var data: Variant = JSON.parse_string(f.get_as_text())
	var steps := 0
	if data != null and data.has("move_history"):
		steps = int(data["move_history"].size())
	var time_text := "?"
	var mt := FileAccess.get_modified_time(_path(slot))
	if mt > 0:
		time_text = Time.get_datetime_string_from_unix_time(int(mt), true)
	return "对局中(第 %d 步)  %s" % [steps, time_text]


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, pos: Vector2, size := Vector2(360, 60)) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.add_theme_font_override("font", _font())
	b.add_theme_font_size_override("font_size", 20)
	Global.style_flat_button(b)
	return b


var _font_cache: Font


func _font() -> Font:
	if _font_cache == null:
		_font_cache = load("res://fonts/zpix.ttf")
	return _font_cache
