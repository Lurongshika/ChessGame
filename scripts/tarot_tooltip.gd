# 塔罗牌技能信息悬浮提示:鼠标悬浮技能卡时,在鼠标右下方显示该牌信息
# 内容:牌面小图 + 技能名 / 类型提示 / 描述
# 用法:场景创建后调用 setup(font),卡悬停时调用 show_for(...),移出时调用 hide_tip()
# 可见时跟随鼠标,自动在屏幕右/下边缘翻转方向
extends Panel

const Tarot := preload("res://scripts/tarot.gd")

const W := 360.0
const PAD := 10.0
const THUMB := 62.0
const FONT_SIZE := 12

var _perk_id := ""
var _font: Font
var pinned := false  # true 时不跟随鼠标(调试/固定展示用)


func setup(font: Font) -> void:
	_font = font
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.06, 0.1, 0.97)
	bg.border_color = Color(0.7, 0.6, 0.4)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", bg)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	visible = false


# 显示技能信息(perks_data 中取 name/tip/desc)
func show_for(perk_id: String, name: String, tip: String, desc: String) -> void:
	hide_tip()
	_perk_id = perk_id

	# 左侧牌面小图(逆位翻转)
	var tex := TextureRect.new()
	tex.position = Vector2(PAD, PAD)
	tex.size = Tarot.card_size(THUMB)
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.texture = Tarot.texture(perk_id)  # 逆位已烘焙翻转
	add_child(tex)

	var tx := PAD + THUMB + 10.0
	var tw := W - PAD - tx

	var t := _label(name, 16, Color(1, 0.92, 0.72))
	t.position = Vector2(tx, 8)
	t.size = Vector2(tw, 24)
	add_child(t)

	var tp := _label(tip, 11, Color(0.68, 0.85, 1.0))
	tp.position = Vector2(tx, 34)
	tp.size = Vector2(tw, 18)
	add_child(tp)

	var d := _label(desc, 11, Color(0.9, 0.88, 0.82))
	d.position = Vector2(tx, 56)
	d.size = Vector2(tw, 130)
	d.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	d.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	add_child(d)

	# 面板高度:牌面小图高度与文字区取大者
	size = Vector2(W, maxf(Tarot.card_size(THUMB).y + PAD * 2, 56 + 130 + PAD))
	visible = true
	queue_redraw()


func hide_tip() -> void:
	_perk_id = ""
	visible = false
	# 子节点均为纯展示控件(无信号连接),立即释放保证确定性
	for c in get_children():
		c.free()


func _process(_delta: float) -> void:
	if not visible or _perk_id.is_empty() or pinned:
		return
	# 跟随鼠标,默认显示在鼠标右下方;越界时翻到左侧/上方
	var m := get_viewport().get_mouse_position()
	var vp := get_viewport_rect().size
	var x := m.x + 14.0
	var y := m.y + 14.0
	if x + size.x > vp.x:
		x = m.x - size.x - 14.0
	if y + size.y > vp.y:
		y = m.y - size.y - 14.0
	position = Vector2(maxf(x, 0.0), maxf(y, 0.0))


func _label(text: String, size_px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
