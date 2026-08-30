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
var showing_card := false  # 当前是否显示技能卡信息(棋子悬停不该覆盖)
var _name_label: Label
var _tip_label: Label
var _desc_vbox: VBoxContainer


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

	var d := _label(desc, 11, Color(0.9, 0.88, 0.82))
	d.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	d.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 描述放入固定宽容器,强制按宽度换行(直接设 size 会被文本最小宽度撑开不换行)
	var dv := VBoxContainer.new()
	dv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dv.add_child(d)
	dv.size = Vector2(tw, 18)
	dv.custom_minimum_size = Vector2(tw, 0)
	_desc_vbox = dv

	# 高度:用估算换行高度 + 行余量(Label 实际换行略多于估算),文本块垂直居中避免下方大片空白
	var est_desc := _font.get_multiline_string_size(desc, HORIZONTAL_ALIGNMENT_LEFT, tw, 11).y + 20.0
	var block_h := 24.0 + 2.0 + 18.0 + 2.0 + est_desc
	var content_h := maxf(Tarot.card_size(THUMB).y + PAD * 2, block_h + PAD * 2)
	size = Vector2(W, content_h)
	var top := maxf(PAD, (content_h - block_h) / 2.0 + PAD)

	var t := _label(name, 16, Color(1, 0.92, 0.72))
	t.position = Vector2(tx, top)
	t.size = Vector2(tw, 24)
	_name_label = t
	add_child(t)

	var tp := _label(tip, 11, Color(0.68, 0.85, 1.0))
	tp.position = Vector2(tx, top + 26.0)
	tp.size = Vector2(tw, 18)
	_tip_label = tp
	add_child(tp)

	dv.position = Vector2(tx, top + 46.0)
	add_child(dv)

	showing_card = true
	visible = true
	queue_redraw()


# 通用文本提示(棋子状态等):标题 + 多行正文,跟随鼠标
func show_text(title: String, body: String) -> void:
	hide_tip()
	showing_card = false
	_perk_id = "__piece__"
	var tw := W - PAD * 2
	var t := _label(title, 16, Color(1, 0.92, 0.72))
	t.position = Vector2(PAD, 9)
	t.size = Vector2(tw, 24)
	add_child(t)
	var d := _label(body, 11, Color(0.9, 0.88, 0.82))
	d.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	d.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dv := VBoxContainer.new()
	dv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dv.add_child(d)
	var body_h := maxf(_font.get_multiline_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, tw, 11).y, 18.0)
	dv.size = Vector2(tw, body_h)
	dv.custom_minimum_size = Vector2(tw, 0)
	dv.position = Vector2(PAD, 38)
	add_child(dv)
	size = Vector2(W, 38.0 + body_h + PAD)
	visible = true
	queue_redraw()


func hide_tip() -> void:
	_perk_id = ""
	showing_card = false
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
