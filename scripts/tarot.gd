# 塔罗牌素材映射:perk_id(技能 id)→ 塔罗大阿卡那牌面
# 正位 = assets/Tarot_Original/8X 下的正位图;逆位 = 同一张图垂直翻转(flip_v)
# 牌面编号 0-21 与 22 张正位技能一一对应(与 PERKS_NORMAL 顺序一致)
extends RefCounted

# 0-21 号牌英文名(文件名用,含空格)
const CARD_NAMES := [
	"The Fool", "The Magician", "The High Priestess", "The Empress", "The Emperor",
	"The Heirophant", "The Lovers", "The Chariot", "Strength", "The Hermit",
	"Wheel of Fortune", "Justice", "The Hanged Man", "Death", "Temperance",
	"The Devil", "The Tower", "The Star", "The Moon", "The Sun",
	"Judgement", "The World",
]

# 正位技能 id → 塔罗编号(0-21);逆位 = 正位 id + "2"(如 yuzhe2)
const CARD_BY_ID := {
	"yuzhe": 0, "moshushi": 1, "nvjisi": 2, "huanghou": 3, "huangdi": 4,
	"jiaohuang": 5, "lianren": 6, "zhanche": 7, "liliang": 8, "yinzhe": 9,
	"mingyun": 10, "zhengyi": 11, "diaodiao": 12, "siwang": 13, "jiezhi": 14,
	"emo": 15, "ta": 16, "xingxing": 17, "yueliang": 18, "taiyang": 19,
	"shenpan": 20, "shijie": 21,
}

const IMG_W := 408.0
const IMG_H := 632.0
const DIR := "res://assets/Tarot_Original/8X"

# 逆位判定:正位 id + "2" 结尾(排除内部标记键如 "_cannon_2")
static func is_reversed(perk_id: String) -> bool:
	return perk_id.ends_with("2") and not perk_id.ends_with("_2")

# 去掉逆位后缀得到正位 id
static func base_id(perk_id: String) -> String:
	if is_reversed(perk_id):
		return perk_id.substr(0, perk_id.length() - 1)
	return perk_id

# 塔罗编号(0-21),未知返回 -1
static func card_index(perk_id: String) -> int:
	return CARD_BY_ID.get(base_id(perk_id), -1)

static func texture_path(perk_id: String) -> String:
	var idx := card_index(perk_id)
	if idx < 0:
		return ""
	return "%s/%d_%s.png" % [DIR, idx, CARD_NAMES[idx]]

static var _flipped_cache := {}  # 逆位已翻转的 ImageTexture(懒加载缓存)


# 返回牌面纹理:正位用原图,逆位已垂直翻转(烘焙进纹理,避免与自定义 shader 的 flip_v 冲突)
static func texture(perk_id: String) -> Texture2D:
	var p := texture_path(perk_id)
	if p.is_empty() or not ResourceLoader.exists(p):
		return null
	var src: Texture2D = load(p)
	if not is_reversed(perk_id):
		return src
	if _flipped_cache.has(perk_id):
		return _flipped_cache[perk_id]
	var img := src.get_image()
	if img == null:
		return src
	img.flip_y()
	var flipped := ImageTexture.create_from_image(img)
	_flipped_cache[perk_id] = flipped
	return flipped

# 按牌面宽高比换算:给定宽度返回标准尺寸
static func card_size(w: float) -> Vector2:
	return Vector2(w, w * IMG_H / IMG_W)
