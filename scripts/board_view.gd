# 棋盘视图:图鉴演示用的自定义绘制控件(独立 _draw,不被背景覆盖)
# 棋子渲染照搬对局中 game.gd 的样式(圆棋子+名字+颜色)
extends Control

const R := preload("res://scripts/chess_rules.gd")

const CELL := 56
const ORIGIN := Vector2(20, 10)  # 节点局部坐标(节点本身已定位在界面中)
const BOARD_W := 8 * CELL
const BOARD_H := 9 * CELL

# 棋子字符映射:小写=红,大写=黑;名字从对局 PIECE_NAMES 取(样式照搬)
const PIECE_CHARS := {
	"r": {"side": 0, "type": 4}, "R": {"side": 1, "type": 4},
	"h": {"side": 0, "type": 3}, "H": {"side": 1, "type": 3},
	"e": {"side": 0, "type": 2}, "E": {"side": 1, "type": 2},
	"a": {"side": 0, "type": 1}, "A": {"side": 1, "type": 1},
	"k": {"side": 0, "type": 0}, "K": {"side": 1, "type": 0},
	"c": {"side": 0, "type": 5}, "C": {"side": 1, "type": 5},
	"p": {"side": 0, "type": 6}, "P": {"side": 1, "type": 6},
}

var board_data: Array = []
var _font_cache: Font
var _piece_tex: ImageTexture


func set_board(b: Array) -> void:
	board_data = b
	queue_redraw()


func _draw() -> void:
	var db: Array = board_data
	if db.is_empty():
		return
	# 画棋盘线
	var line := Color(0.55, 0.42, 0.28)
	for i in 10:
		var y := ORIGIN.y + i * CELL
		draw_line(Vector2(ORIGIN.x, y), Vector2(ORIGIN.x + BOARD_W, y), line, 2.0)
	for i in 9:
		var x := ORIGIN.x + i * CELL
		draw_line(Vector2(x, ORIGIN.y), Vector2(x, ORIGIN.y + BOARD_H), line, 2.0)
	# 楚河汉界
	_draw_text(Vector2(ORIGIN.x + BOARD_W * 0.25, ORIGIN.y + 4.5 * CELL), "楚河", 26, Color(0.45, 0.35, 0.22))
	_draw_text(Vector2(ORIGIN.x + BOARD_W * 0.75, ORIGIN.y + 4.5 * CELL), "汉界", 26, Color(0.45, 0.35, 0.22))
	# 画棋子
	for r in 10:
		for c in 9:
			var ch: String = str(db[r][c])
			if ch == "." or ch == "":
				continue
			if not PIECE_CHARS.has(ch):
				continue
			var info: Dictionary = PIECE_CHARS[ch]
			var center := ORIGIN + Vector2(c, r) * CELL
			draw_texture_rect(_piece_texture(), Rect2(center - Vector2(24, 24), Vector2(48, 48)), false, Color(0.3, 0.22, 0.14))
			draw_texture_rect(_piece_texture(), Rect2(center - Vector2(23, 23), Vector2(46, 46)), false, Color(0.95, 0.9, 0.78))
			# 名字与颜色照搬对局:红=帅炮兵仕相马车,黑=將砲卒士象馬車
			var nm: String = R.PIECE_NAMES[info["type"]] if info["side"] == 0 else R.PIECE_NAMES_BLACK[info["type"]]
			var color := Color(0.75, 0.15, 0.12) if info["side"] == 0 else Color(0.15, 0.13, 0.12)
			_draw_text(center + Vector2(3, -1), nm, 27, color)


func _font() -> Font:
	if _font_cache == null:
		_font_cache = load("res://fonts/zpix.ttf")
	return _font_cache


func _piece_texture() -> ImageTexture:
	if _piece_tex == null:
		var s := 48
		var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
		var cc := Vector2(s / 2.0, s / 2.0)
		for y in s:
			for x in s:
				img.set_pixel(x, y, Color(1, 1, 1, 1) if Vector2(x, y).distance_to(cc) <= 23.0 else Color(0, 0, 0, 0))
		_piece_tex = ImageTexture.create_from_image(img)
	return _piece_tex


func _draw_text(center: Vector2, text: String, font_size: int, color: Color) -> void:
	var f := _font()
	var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline_y := center.y + (f.get_ascent(font_size) - f.get_descent(font_size)) / 2.0
	draw_string(f, Vector2(center.x - ts.x / 2.0, baseline_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
