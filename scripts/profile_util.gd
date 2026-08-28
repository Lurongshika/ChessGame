# 用户资料工具:读取/生成头像与用户名
extends RefCounted

const PROFILE_PATH := "user://profile.json"
# 用户图标 SVG(内嵌,避免导出后读不到原始文件)
const SVG_ICON := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"256\" height=\"256\" viewBox=\"0 0 22 22\"><path fill=\"currentColor\" d=\"M4 2h14v1h1v1h1v14h-1v1h-1v1H4v-1H3v-1H2V4h1V3h1zm0 14h1v-1h2v-1h8v1h2v1h1V5h-1V4H5v1H4zm12 2v-1h-2v-1H8v1H6v1zM9 5h4v1h1v1h1v4h-1v1h-1v1H9v-1H8v-1H7V7h1V6h1zm3 3V7h-2v1H9v2h1v1h2v-1h1V8z\"></path></svg>"


static func load_profile() -> Dictionary:
	if not FileAccess.file_exists(PROFILE_PATH):
		return {}
	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		return data
	return {}


static func username(p: Dictionary) -> String:
	var n: String = p.get("username", "")
	if n.is_empty():
		n = "未设置"
	return n


static func profile_color(p: Dictionary) -> Color:
	var col = p.get("color", [])
	if col.size() == 3:
		return Color(float(col[0]), float(col[1]), float(col[2]))
	return Color(0.35, 0.6, 0.9)


static func color_icon(color: Color, size: int) -> ImageTexture:
	var hex := "#%02x%02x%02x" % [int(color.r * 255), int(color.g * 255), int(color.b * 255)]
	var colored := SVG_ICON.replace("currentColor", hex)
	var img := Image.new()
	img.load_svg_from_buffer(colored.to_utf8_buffer())
	img.resize(size, size, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


# 本地资料头像(自定义头像优先)
static func avatar_icon(p: Dictionary, size: int) -> Texture2D:
	if bool(p.get("custom_avatar", false)) and FileAccess.file_exists("user://avatar.png"):
		var img := Image.new()
		if img.load("user://avatar.png") == OK:
			img.resize(size, size, Image.INTERPOLATE_LANCZOS)
			return ImageTexture.create_from_image(img)
	return color_icon(profile_color(p), size)


# 联机传输用:打包自己资料(含自定义头像 PNG 字节)
static func to_net_data() -> Dictionary:
	var p := load_profile()
	var d := {
		"username": p.get("username", "玩家"),
		"custom_avatar": bool(p.get("custom_avatar", false)),
		"color_prefs": p.get("color_prefs", []),
	}
	# 头像底色:取第一个颜色偏好(旧存档兼容 color 字段)
	var prefs: Array = d["color_prefs"]
	if not prefs.is_empty():
		d["color"] = _pref_to_rgb(int(prefs[0]))
	else:
		d["color"] = p.get("color", [0.35, 0.6, 0.9])
	if d["custom_avatar"] and FileAccess.file_exists("user://avatar.png"):
		var f := FileAccess.open("user://avatar.png", FileAccess.READ)
		d["avatar_png"] = f.get_buffer(f.get_length())
	return d


# COLORS16 索引 → [r,g,b]
static func _pref_to_rgb(idx: int) -> Array:
	var cols := Global.COLORS16
	if idx >= 0 and idx < cols.size():
		var c: Color = cols[idx]
		return [c.r, c.g, c.b]
	return [0.35, 0.6, 0.9]
