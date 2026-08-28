# 中国象棋规则引擎(纯逻辑,不依赖渲染)
# 棋盘 board[row][col]:row 0 = 黑方底线,row 9 = 红方底线;col 0..8
# 棋子:Dictionary { "side": Side, "type": Type } 或 null
extends RefCounted

const COLS := 9
const ROWS := 10

enum Side { RED, BLACK, GREEN, BLUE }
enum Type { KING, ADVISOR, ELEPHANT, HORSE, ROOK, CANNON, PAWN, QUEEN }

const PIECE_NAMES := {
	Type.KING: "帅", Type.ADVISOR: "仕", Type.ELEPHANT: "相",
	Type.HORSE: "马", Type.ROOK: "车", Type.CANNON: "炮", Type.PAWN: "兵", Type.QUEEN: "后",
}
const PIECE_NAMES_BLACK := {
	Type.KING: "将", Type.ADVISOR: "士", Type.ELEPHANT: "象",
	Type.HORSE: "马", Type.ROOK: "车", Type.CANNON: "炮", Type.PAWN: "卒", Type.QUEEN: "后",
}


static func make_piece(side: int, type: int) -> Dictionary:
	return {"side": side, "type": type}


static func make_board() -> Array:
	var b: Array = []
	for r in ROWS:
		var row: Array = []
		for c in COLS:
			row.append(null)
		b.append(row)
	var back := [
		Type.ROOK, Type.HORSE, Type.ELEPHANT, Type.ADVISOR, Type.KING,
		Type.ADVISOR, Type.ELEPHANT, Type.HORSE, Type.ROOK,
	]
	for c in COLS:
		b[0][c] = make_piece(Side.BLACK, back[c])
		b[9][c] = make_piece(Side.RED, back[c])
	b[2][1] = make_piece(Side.BLACK, Type.CANNON)
	b[2][7] = make_piece(Side.BLACK, Type.CANNON)
	b[7][1] = make_piece(Side.RED, Type.CANNON)
	b[7][7] = make_piece(Side.RED, Type.CANNON)
	for c in [0, 2, 4, 6, 8]:
		b[3][c] = make_piece(Side.BLACK, Type.PAWN)
		b[6][c] = make_piece(Side.RED, Type.PAWN)
	return b


# 四人模式半场字符布局(4行×9列,黑方在上、红方在下;绿/蓝用红/黑半场旋转)
const HALF4_BLACK := [
	"RHEAKAEHR",
	".........",
	".C.....C.",
	"P.P.P.P.P",
]
const HALF4_RED := [
	"p.p.p.p.p",
	".c.....c.",
	".........",
	"rheakaehr",
]


static func _char4_type(ch: String) -> int:
	match ch:
		"k", "K": return Type.KING
		"a", "A": return Type.ADVISOR
		"e", "E": return Type.ELEPHANT
		"h", "H": return Type.HORSE
		"r", "R": return Type.ROOK
		"c", "C": return Type.CANNON
		"p", "P": return Type.PAWN
	return -1


# 四人模式初始棋盘 17×17(四个半场围中心 9×9 空位)
static func make_board4() -> Array:
	var b: Array = []
	for y in 17:
		var row: Array = []
		for x in 17:
			row.append(null)
		b.append(row)
	_place4(b, HALF4_BLACK, Side.BLACK, Vector2i(4, 0), false)   # 上:黑
	_place4(b, HALF4_RED, Side.RED, Vector2i(4, 13), false)     # 下:红
	_place4(b, HALF4_RED, Side.GREEN, Vector2i(0, 4), true)     # 左:绿
	_place4(b, HALF4_BLACK, Side.BLUE, Vector2i(13, 4), true)   # 右:蓝
	return b


static func _place4(b: Array, half: Array, side: int, origin: Vector2i, vertical: bool) -> void:
	var rows: int = half.size()
	var cols: int = half[0].length()
	for y in rows:
		for x in cols:
			var ch: String = str(half[y][x])
			if ch == "." or ch == "":
				continue
			var tx: int
			var ty: int
			if vertical:
				tx = origin.x + (rows - 1 - y)
				ty = origin.y + x
			else:
				tx = origin.x + x
				ty = origin.y + y
			b[ty][tx] = make_piece(side, _char4_type(ch))


static func clone_board(board: Array) -> Array:
	var nb: Array = []
	for row in board:
		nb.append(row.duplicate())
	return nb


static func in_board(pos: Vector2i, b: Array = []) -> bool:
	if b.is_empty():
		return pos.x >= 0 and pos.x < COLS and pos.y >= 0 and pos.y < ROWS
	return pos.x >= 0 and pos.x < b[0].size() and pos.y >= 0 and pos.y < b.size()


# 四人模式:每方半场范围与兵前进方向(side 0=红/下,1=黑/上,2=绿/左,3=蓝/右)
const ARMS4 := {
	1: {"min_x": 4, "max_x": 12, "min_y": 0, "max_y": 3, "fwd": Vector2i(0, 1)},
	0: {"min_x": 4, "max_x": 12, "min_y": 13, "max_y": 16, "fwd": Vector2i(0, -1)},
	2: {"min_x": 0, "max_x": 3, "min_y": 4, "max_y": 12, "fwd": Vector2i(1, 0)},
	3: {"min_x": 13, "max_x": 16, "min_y": 4, "max_y": 12, "fwd": Vector2i(-1, 0)},
}


# 兵的前进方向(双人红上黑下;四人按朝向)
static func pawn_fwd(side: int) -> Vector2i:
	match side:
		Side.RED: return Vector2i(0, -1)
		Side.BLACK: return Vector2i(0, 1)
		2: return Vector2i(1, 0)
		3: return Vector2i(-1, 0)
	return Vector2i(0, -1)


# 某格是否在己方四人半场(四人模式)
static func in_arm4(pos: Vector2i, side: int) -> bool:
	if not ARMS4.has(side):
		return false
	var a: Dictionary = ARMS4[side]
	return pos.x >= a["min_x"] and pos.x <= a["max_x"] and pos.y >= a["min_y"] and pos.y <= a["max_y"]


static func piece_at(board: Array, pos: Vector2i) -> Dictionary:
	if not in_board(pos, board):
		return {}
	var p = board[pos.y][pos.x]
	return p if p != null else {}


static func find_king(board: Array, side: int) -> Vector2i:
	# 按棋盘实际尺寸遍历(四人 17×17 王在 y>=10,双人 ROWS/COLS 会漏)
	var n_r: int = board.size()
	var n_c: int = board[0].size() if n_r > 0 else 0
	for r in n_r:
		for c in n_c:
			var p := piece_at(board, Vector2i(c, r))
			if p.get("side", -1) == side and p.get("type", -1) == Type.KING:
				return Vector2i(c, r)
	return Vector2i(-1, -1)


static func perks_of(side: int, perks_red: Dictionary, perks_black: Dictionary) -> Dictionary:
	return perks_red if side == Side.RED else perks_black


# 某个子所有可移动/可吃目标(不考虑走完自己被将军)
static func raw_moves(board: Array, pos: Vector2i, perks_red: Dictionary, perks_black: Dictionary) -> Array[Vector2i]:
	var p := piece_at(board, pos)
	if p.is_empty():
		return []
	var side: int = p["side"]
	var perks := perks_of(side, perks_red, perks_black)
	var moves: Array[Vector2i] = []
	match p["type"]:
		Type.KING:
			moves = _king_moves(board, pos, side, perks)
		Type.ADVISOR:
			moves = _advisor_moves(board, pos, side, perks)
		Type.ELEPHANT:
			moves = _elephant_moves(board, pos, side, perks)
		Type.HORSE:
			moves = _horse_moves(board, pos, side, perks)
		Type.ROOK:
			moves = _rook_moves(board, pos, side, perks)
		Type.CANNON:
			moves = _cannon_moves(board, pos, side, perks)
		Type.PAWN:
			moves = _pawn_moves(board, pos, side, perks)
		Type.QUEEN:
			moves = _queen_moves(board, pos, side)
	# 塔(进阶):所有子可八向移动一格
	if perks.has("ta2"):
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var t2: Vector2i = pos + d
			if in_board(t2) and (piece_at(board, t2).is_empty() or piece_at(board, t2)["side"] != side):
				moves.append(t2)
	var result: Array[Vector2i] = []
	for m in moves:
		var target := piece_at(board, m)
		if target.is_empty() or target["side"] != side:
			result.append(m)
	return result


static func _in_palace(pos: Vector2i, side: int, board: Array = []) -> bool:
	# 四人棋盘 17×17:按棋盘尺寸区分双人/四人
	var is_four := (not board.is_empty() and board.size() == 17)
	if is_four:
		# 四人:王周围 3×2(以王所在半场为中心)
		if board.is_empty():
			return false
		var king := find_king(board, side)
		if king.x < 0:
			return false
		return absi(pos.x - king.x) <= 1 and absi(pos.y - king.y) <= 1 and in_board(pos, board)
	if side == Side.RED:
		return pos.x >= 3 and pos.x <= 5 and pos.y >= 7 and pos.y <= 9
	if side == Side.BLACK:
		return pos.x >= 3 and pos.x <= 5 and pos.y >= 0 and pos.y <= 2
	return false


static func _king_moves(board: Array, pos: Vector2i, side: int, perks: Dictionary) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var t: Vector2i = pos + d
		if _in_palace(t, side, board):
			moves.append(t)
	return moves


static func _advisor_moves(board: Array, pos: Vector2i, side: int, perks: Dictionary) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	for d in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var t: Vector2i = pos + d
		# 必须传 board:四人 17×17 下默认尺寸(9×10)会误判出界,九宫也依赖棋盘
		if in_board(t, board) and _in_palace(t, side, board):
			moves.append(t)
	return moves


static func _elephant_moves(board: Array, pos: Vector2i, side: int, perks: Dictionary) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	if perks.has("yueliang") or perks.has("yueliang2"):
		# 飞象:沿四个斜方向任意距离,路径必须为空;可吃路径上第一个子
		for d in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var t: Vector2i = pos + d
			while in_board(t, board):
				moves.append(t)
				if not piece_at(board, t).is_empty():
					break
				t += d
		return moves
	# 普通象:田字 + 象眼 + 河界
	for d in [Vector2i(2, 2), Vector2i(2, -2), Vector2i(-2, 2), Vector2i(-2, -2)]:
		var t: Vector2i = pos + d
		if not in_board(t, board):
			continue
		if side == Side.RED and t.y < 5:
			continue
		if side == Side.BLACK and t.y > 4:
			continue
		if side == Side.GREEN or side == Side.BLUE:
			if not in_arm4(t, side):
				continue
		var eye := pos + Vector2i(d.x / 2, d.y / 2)
		if piece_at(board, eye).is_empty():
			moves.append(t)
	return moves


static func _horse_moves(board: Array, pos: Vector2i, side: int, perks: Dictionary) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	var flying := perks.has("zhengyi")
	# 8 个日字目标;马腿 = 日字"长边"(2 格)方向的第一步
	for t in [
		Vector2i(1, 2), Vector2i(-1, 2), Vector2i(1, -2), Vector2i(-1, -2),
		Vector2i(2, 1), Vector2i(2, -1), Vector2i(-2, 1), Vector2i(-2, -1),
	]:
		var target: Vector2i = pos + t
		if not in_board(target, board):
			continue
		var leg: Vector2i
		if absi(t.x) == 2:
			leg = pos + Vector2i(signi(t.x), 0)   # 长边在横向 → 马腿在左/右一格
		else:
			leg = pos + Vector2i(0, signi(t.y))   # 长边在纵向 → 马腿在上/下一格
		if flying or piece_at(board, leg).is_empty():
			moves.append(target)
	# 正义:马还能落到另一匹马所能落位的位置(另一马不别腿的落位)
	if flying:
		for r in ROWS:
			for c in COLS:
				var op := Vector2i(c, r)
				if op == pos:
					continue
				var other := piece_at(board, op)
				if other.is_empty() or other["type"] != Type.HORSE:
					continue
				for t2 in [
					Vector2i(1, 2), Vector2i(-1, 2), Vector2i(1, -2), Vector2i(-1, -2),
					Vector2i(2, 1), Vector2i(2, -1), Vector2i(-2, 1), Vector2i(-2, -1),
				]:
					var target2: Vector2i = op + t2
					if not in_board(target2, board) or target2 == pos:
						continue
					var leg2: Vector2i
					if absi(t2.x) == 2:
						leg2 = op + Vector2i(signi(t2.x), 0)
					else:
						leg2 = op + Vector2i(0, signi(t2.y))
					if piece_at(board, leg2).is_empty():
						if not target2 in moves:
							moves.append(target2)
	return moves


static func _rook_moves(board: Array, pos: Vector2i, side: int, perks: Dictionary) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var t: Vector2i = pos + d
		while in_board(t, board):
			moves.append(t)
			if not piece_at(board, t).is_empty():
				break
			t += d
	if perks.has("taiyang"):
		for d in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var t: Vector2i = pos + d
			if in_board(t, board):
				moves.append(t)
	# 太阳(进阶):己方没有炮时,车八向无限距离移动
	if perks.has("taiyang2"):
		var has_own_cannon := false
		for r in ROWS:
			for c in COLS:
				var cp := piece_at(board, Vector2i(c, r))
				if not cp.is_empty() and cp["side"] == side and cp["type"] == Type.CANNON:
					has_own_cannon = true
					break
			if has_own_cannon:
				break
		if not has_own_cannon:
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
				var t: Vector2i = pos + d
				while in_board(t, board):
					moves.append(t)
					if not piece_at(board, t).is_empty():
						break
					t += d
	return moves


static func _cannon_moves(board: Array, pos: Vector2i, side: int, perks: Dictionary) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	# 普通炮:隔 1 个子吃;正义(进阶)释放后切换为隔 2 个子吃(_cannon_2 状态键)
	var screens := 2 if perks.has("_cannon_2") else 1
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var t: Vector2i = pos + d
		var count := 0
		while in_board(t, board):
			if piece_at(board, t).is_empty():
				if count == 0:
					moves.append(t)
			else:
				count += 1
				if count >= 2 and count <= screens + 1:
					moves.append(t)
					if count == screens + 1:
						break
			t += d
	return moves


static func _pawn_moves(board: Array, pos: Vector2i, side: int, perks: Dictionary) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	var fwd: Vector2i = pawn_fwd(side)
	var crossed: bool
	if side == Side.RED:
		crossed = pos.y <= 4
	elif side == Side.BLACK:
		crossed = pos.y >= 5
	else:
		crossed = not in_arm4(pos, side)  # 四人:离开己方半场=过河
	var t: Vector2i = pos + fwd
	if in_board(t, board):
		moves.append(t)
	if crossed:
		# 过河兵可横走(垂直前进方向的左右)
		var perp := Vector2i(-fwd.y, fwd.x)
		for d in [perp, -perp]:
			var s2: Vector2i = pos + d
			if in_board(s2, board):
				moves.append(s2)
		# 塔:过河兵可斜向前吃子(仅吃子,不能斜走空位)
		if perks.has("ta"):
			for d in [perp, -perp]:
				var td: Vector2i = pos + d + fwd
				if in_board(td, board) and not piece_at(board, td).is_empty():
					moves.append(td)
	return moves


# 四人模式:raw_moves 的 4 方版本,perks4 是 4 元素数组(按 side 索引)
static func raw_moves4(board: Array, pos: Vector2i, perks4: Array) -> Array[Vector2i]:
	var p := piece_at(board, pos)
	if p.is_empty():
		return []
	var side: int = p["side"]
	var perks: Dictionary = perks4[side] if side >= 0 and side < perks4.size() else {}
	var moves: Array[Vector2i] = []
	match p["type"]:
		Type.KING:
			moves = _king_moves(board, pos, side, perks)
		Type.ADVISOR:
			moves = _advisor_moves(board, pos, side, perks)
		Type.ELEPHANT:
			moves = _elephant_moves(board, pos, side, perks)
		Type.HORSE:
			moves = _horse_moves(board, pos, side, perks)
		Type.ROOK:
			moves = _rook_moves(board, pos, side, perks)
		Type.CANNON:
			moves = _cannon_moves(board, pos, side, perks)
		Type.PAWN:
			moves = _pawn_moves(board, pos, side, perks)
		Type.QUEEN:
			moves = _queen_moves(board, pos, side)
	# 塔(进阶):所有子可八向移动一格
	if perks.has("ta2"):
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var t2: Vector2i = pos + d
			if in_board(t2, board) and (piece_at(board, t2).is_empty() or piece_at(board, t2)["side"] != side):
				moves.append(t2)
	var result: Array[Vector2i] = []
	for m in moves:
		var target := piece_at(board, m)
		if target.is_empty() or target["side"] != side:
			result.append(m)
	return result


# 后:八向不限距离移动(不能越子)
static func _queen_moves(board: Array, pos: Vector2i, side: int) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var t: Vector2i = pos + d
		while in_board(t, board):
			moves.append(t)
			if not piece_at(board, t).is_empty():
				break
			t += d
	return moves


# 应用走法,返回 {"board": 新棋盘, "captured": 被吃的子(null 或 Dictionary)}
static func apply_move(board: Array, from: Vector2i, to: Vector2i) -> Dictionary:
	var nb := clone_board(board)
	var p = nb[from.y][from.x]
	nb[from.y][from.x] = null
	var captured = nb[to.y][to.x]
	nb[to.y][to.x] = p
	return {"board": nb, "captured": captured}


static func is_in_check(board: Array, side: int, perks_red: Dictionary, perks_black: Dictionary) -> bool:
	var king := find_king(board, side)
	if king.x < 0:
		return false
	var enemy := 1 - side
	for r in ROWS:
		for c in COLS:
			var pos := Vector2i(c, r)
			var p := piece_at(board, pos)
			if p.get("side", -1) == enemy:
				if king in raw_moves(board, pos, perks_red, perks_black):
					return true
	return false


# 合法着法:raw_moves 过滤掉"走完后己方王被将军"的着法(吃对方王除外)
static func legal_moves(board: Array, pos: Vector2i, perks_red: Dictionary, perks_black: Dictionary) -> Array[Vector2i]:
	var p := piece_at(board, pos)
	if p.is_empty():
		return []
	var side: int = p["side"]
	var result: Array[Vector2i] = []
	for t in raw_moves(board, pos, perks_red, perks_black):
		var target := piece_at(board, t)
		if target.get("type", -1) == Type.KING and target.get("side", -1) != side:
			result.append(t)
			continue
		var res := apply_move(board, pos, t)
		if not is_in_check(res["board"], side, perks_red, perks_black):
			result.append(t)
	return result


static func has_legal_move(board: Array, side: int, perks_red: Dictionary, perks_black: Dictionary) -> bool:
	for r in ROWS:
		for c in COLS:
			var pos := Vector2i(c, r)
			var p := piece_at(board, pos)
			if p.get("side", -1) == side:
				if not legal_moves(board, pos, perks_red, perks_black).is_empty():
					return true
	return false
