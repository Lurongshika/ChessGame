# 中国象棋 AI:negamax alpha-beta + 静态搜索 + 历史启发式排序 + Zobrist 置换表 + 子力/位置表估值
# 借鉴 pengjiu/ChineseChess(NegaScout/剪枝/排序/置换表)与 lhartikk/simple-chess-ai(minimax+PST)思路。
extends RefCounted

const R := preload("res://scripts/chess_rules.gd")

const VALUES := {
	R.Type.KING: 10000.0, R.Type.ADVISOR: 2.0, R.Type.ELEPHANT: 2.0,
	R.Type.HORSE: 4.0, R.Type.ROOK: 9.0, R.Type.CANNON: 4.5,
	R.Type.PAWN: 1.0, R.Type.QUEEN: 12.0,
}

const TIME_LIMIT_2P := 800
const TIME_LIMIT_4P := 380
const MAX_DEPTH_2P := 3
const MAX_DEPTH_4P := 2
const QUIESCE_CAP := 6
const INF := 900000.0
const MATE := 100000.0

# ---------- 静态搜索数据 ----------
static var _tt := {}
static var _history := {}
static var _zob := {}
static var _zside := []
static var _zinit := false

# ---------- 位置表(红方视角,10 行×9 列;黑方行镜像) ----------
const PST_PAWN := [0.0,0,0,0,0,0,0,0,0, 4.0,3.8,3.4,3.0,2.8,3.0,3.4,3.8,4.0, 3.4,3.2,2.8,2.4,2.2,2.4,2.8,3.2,3.4, 2.6,2.4,2.0,1.6,1.4,1.6,2.0,2.4,2.6, 2.0,1.8,1.4,1.0,0.8,1.0,1.4,1.8,2.0, 1.2,1.0,0.6,0.2,0.0,0.2,0.6,1.0,1.2, 0.6,0.5,0.3,0.1,0.0,0.1,0.3,0.5,0.6, 0.3,0.2,0.1,0.0,0.0,0.0,0.1,0.2,0.3, 0.2,0.1,0.1,0.0,0.0,0.0,0.1,0.1,0.2, 0.1,0.1,0.0,0.0,0.0,0.0,0.0,0.1,0.1]
const PST_HORSE := [0.4,0.5,0.6,0.7,0.7,0.7,0.6,0.5,0.4, 0.6,0.8,1.0,1.1,1.1,1.1,1.0,0.8,0.6, 0.8,1.1,1.3,1.5,1.5,1.5,1.3,1.1,0.8, 0.9,1.2,1.5,1.7,1.8,1.7,1.5,1.2,0.9, 0.8,1.1,1.4,1.6,1.7,1.6,1.4,1.1,0.8, 0.7,1.0,1.3,1.5,1.5,1.5,1.3,1.0,0.7, 0.5,0.7,0.9,1.0,1.0,1.0,0.9,0.7,0.5, 0.4,0.5,0.6,0.7,0.7,0.7,0.6,0.5,0.4, 0.3,0.4,0.5,0.5,0.5,0.5,0.5,0.4,0.3, 0.2,0.3,0.4,0.4,0.4,0.4,0.4,0.3,0.2]
const PST_CANNON := [0.6,0.6,0.6,0.6,0.6,0.6,0.6,0.6,0.6, 0.7,0.8,0.7,0.7,0.7,0.7,0.7,0.8,0.7, 0.8,0.9,0.9,0.9,0.9,0.9,0.9,0.9,0.8, 0.7,0.9,0.9,1.0,1.0,1.0,0.9,0.9,0.7, 0.7,0.9,1.0,1.1,1.2,1.1,1.0,0.9,0.7, 0.7,0.9,1.0,1.1,1.2,1.1,1.0,0.9,0.7, 0.7,0.9,0.9,1.0,1.0,1.0,0.9,0.9,0.7, 0.8,0.9,0.9,0.9,0.9,0.9,0.9,0.9,0.8, 0.7,0.8,0.7,0.7,0.7,0.7,0.7,0.8,0.7, 0.6,0.6,0.6,0.6,0.6,0.6,0.6,0.6,0.6]
const PST_ROOK := [0.6,0.8,0.8,0.8,0.9,0.8,0.8,0.8,0.6, 0.8,1.0,1.0,1.0,1.0,1.0,1.0,1.0,0.8, 0.9,1.2,1.2,1.2,1.2,1.2,1.2,1.2,0.9, 1.0,1.3,1.3,1.4,1.4,1.4,1.3,1.3,1.0, 1.0,1.3,1.3,1.4,1.4,1.4,1.3,1.3,1.0, 1.0,1.3,1.3,1.4,1.4,1.4,1.3,1.3,1.0, 1.0,1.2,1.2,1.3,1.3,1.3,1.2,1.2,1.0, 0.9,1.1,1.1,1.2,1.2,1.2,1.1,1.1,0.9, 0.8,1.0,1.0,1.0,1.0,1.0,1.0,1.0,0.8, 0.6,0.8,0.8,0.8,0.9,0.8,0.8,0.8,0.6]
const PST_ADVISOR := [0.0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0, 0,0,0,0,0.6,0,0,0,0, 0,0,0,0,0.8,0,0,0,0, 0,0,0,0,0.6,0,0,0,0, 0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0]
const PST_ELEPHANT := [0.0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0, 0,0,0,0.4,0,0.4,0,0,0, 0,0,0,0.4,0,0,0.4,0,0, 0,0,0,0,0.6,0,0,0,0, 0,0,0,0.4,0,0,0.4,0,0, 0,0,0,0,0.4,0,0.4,0,0, 0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0]


static func choose_move(board: Array, side: int, perks_red: Dictionary, perks_black: Dictionary) -> Dictionary:
	_zinit_check()
	_tt.clear(); _history.clear()
	var deadline := Time.get_ticks_msec() + TIME_LIMIT_2P
	var best := _search_root(board, side, perks_red, perks_black, MAX_DEPTH_2P, deadline)
	return best if not best.is_empty() else _greedy_fallback(board, side, perks_red, perks_black)


static func choose_move4(board: Array, side: int, perks4: Array) -> Dictionary:
	var deadline := Time.get_ticks_msec() + TIME_LIMIT_4P
	var best := {}
	for depth in range(1, MAX_DEPTH_4P + 1):
		var root_best := {}
		var rs := -INF
		var timed_out := false
		for mv in _ordered_moves4(board, side, perks4):
			if Time.get_ticks_msec() > deadline:
				timed_out = true
				break
			var res := R.apply_move(board, mv["from"], mv["to"])
			var score := -_negamax4(res["board"], 1 - side, depth - 1, -INF, INF, perks4, deadline)
			if score > rs:
				rs = score; root_best = mv
		if timed_out:
			break
		if not root_best.is_empty():
			best = root_best
	return best if not best.is_empty() else _greedy_fallback4(board, side, perks4)


static func _search_root(board: Array, side: int, perks_red: Dictionary, perks_black: Dictionary, max_depth: int, deadline: int) -> Dictionary:
	var best := {}
	for depth in range(1, max_depth + 1):
		var root_best := {}
		var rs := -INF
		var ra := -INF
		var timed_out := false
		for mv in _ordered_moves(board, side, perks_red, perks_black):
			if Time.get_ticks_msec() > deadline:
				timed_out = true
				break
			var res := R.apply_move(board, mv["from"], mv["to"])
			var score := -_negamax(res["board"], 1 - side, depth - 1, -INF, -ra, perks_red, perks_black, deadline)
			if score > rs:
				rs = score; root_best = mv
			ra = maxf(ra, score)
		if timed_out:
			break
		if not root_best.is_empty():
			best = root_best
	return best


static func _negamax(board: Array, side: int, depth: int, alpha: float, beta: float, perks_red: Dictionary, perks_black: Dictionary, deadline: int) -> float:
	if Time.get_ticks_msec() > deadline:
		return 0.0
	if depth <= 0:
		return _quiescence(board, side, alpha, beta, perks_red, perks_black, deadline, 0)
	var key := _hash(board, side)
	var entry = _tt.get(key)
	if entry != null and entry["depth"] >= depth:
		if entry["flag"] == 0 or (entry["flag"] == 1 and entry["score"] >= beta) or (entry["flag"] == 2 and entry["score"] <= alpha):
			return entry["score"]
	var moves := _ordered_moves(board, side, perks_red, perks_black)
	if moves.is_empty():
		var sc := -MATE + depth if R.is_in_check(board, side, perks_red, perks_black) else -50.0
		_tt[key] = {"depth": 64, "score": sc, "flag": 0}
		return sc
	var best := -INF
	var a := alpha
	var flag := 2
	for mv in moves:
		if Time.get_ticks_msec() > deadline:
			break
		var res := R.apply_move(board, mv["from"], mv["to"])
		var score := -_negamax(res["board"], 1 - side, depth - 1, -beta, -a, perks_red, perks_black, deadline)
		if score > best:
			best = score
		if best > a:
			a = best
		if a >= beta:
			flag = 1
			_history[_mvkey(mv["from"], mv["to"])] = _history.get(_mvkey(mv["from"], mv["to"]), 0.0) + float(depth * depth)
			break
	if best > alpha and best < beta:
		flag = 0
	_tt[key] = {"depth": depth, "score": best, "flag": flag}
	return best


# 静态搜索:只扩展吃子,直到静局面,防 horizon effect
static func _quiescence(board: Array, side: int, alpha: float, beta: float, perks_red: Dictionary, perks_black: Dictionary, deadline: int, qd: int) -> float:
	var stand := _evaluate(board, side, perks_red, perks_black)
	if qd >= QUIESCE_CAP or Time.get_ticks_msec() > deadline:
		return stand
	if stand >= beta:
		return stand
	if stand > alpha:
		alpha = stand
	for mv in _captures(board, side, perks_red, perks_black):
		if Time.get_ticks_msec() > deadline:
			return alpha
		var res := R.apply_move(board, mv["from"], mv["to"])
		var score := -_quiescence(res["board"], 1 - side, -beta, -alpha, perks_red, perks_black, deadline, qd + 1)
		if score >= beta:
			return score
		if score > alpha:
			alpha = score
	return alpha


static func _negamax4(board: Array, side: int, depth: int, alpha: float, beta: float, perks4: Array, deadline: int) -> float:
	if Time.get_ticks_msec() > deadline:
		return 0.0
	if depth <= 0:
		return _evaluate4(board, side, perks4)
	var moves := _ordered_moves4(board, side, perks4)
	if moves.is_empty():
		return -MATE + depth
	var best := -INF
	var a := alpha
	for mv in moves:
		if Time.get_ticks_msec() > deadline:
			break
		var res := R.apply_move(board, mv["from"], mv["to"])
		var score := -_negamax4(res["board"], 1 - side, depth - 1, -beta, -a, perks4, deadline)
		if score > best:
			best = score
		a = maxf(a, score)
		if a >= beta:
			break
	return best


static func _ordered_moves(board: Array, side: int, perks_red: Dictionary, perks_black: Dictionary) -> Array:
	var moves: Array = []
	for r in R.ROWS:
		for c in R.COLS:
			var p = board[r][c]
			if p == null or p["side"] != side:
				continue
			var pos := Vector2i(c, r)
			for t in R.legal_moves(board, pos, perks_red, perks_black):
				var cap = board[t.y][t.x]
				var s: float = 0.0
				if cap != null:
					s = 100000.0 + VALUES.get(cap["type"], 1.0) * 10.0 - VALUES.get(p["type"], 1.0) * 0.1
				else:
					s = _history.get(_mvkey(pos, t), 0.0)
				moves.append({"from": pos, "to": t, "score": s})
	moves.sort_custom(func(a, b): return a["score"] > b["score"])
	return moves


static func _captures(board: Array, side: int, perks_red: Dictionary, perks_black: Dictionary) -> Array:
	var caps: Array = []
	for r in R.ROWS:
		for c in R.COLS:
			var p = board[r][c]
			if p == null or p["side"] != side:
				continue
			var pos := Vector2i(c, r)
			for t in R.legal_moves(board, pos, perks_red, perks_black):
				if board[t.y][t.x] != null:
					var v: float = VALUES.get(board[t.y][t.x]["type"], 1.0) * 10.0 - VALUES.get(p["type"], 1.0) * 0.1
					caps.append({"from": pos, "to": t, "score": v})
	caps.sort_custom(func(a, b): return a["score"] > b["score"])
	return caps


static func _ordered_moves4(board: Array, side: int, perks4: Array) -> Array:
	var moves: Array = []
	for r in board.size():
		for c in board[r].size():
			var p = board[r][c]
			if p == null or p["side"] != side:
				continue
			var pos := Vector2i(c, r)
			for t in R.raw_moves4(board, pos, perks4):
				var cap = board[t.y][t.x]
				var s: float = 0.0
				if cap != null:
					s = 100000.0 + VALUES.get(cap["type"], 1.0) * 10.0
				moves.append({"from": pos, "to": t, "score": s})
	moves.sort_custom(func(a, b): return a["score"] > b["score"])
	return moves


static func _mvkey(f: Vector2i, t: Vector2i) -> String:
	return "%d,%d|%d,%d" % [f.x, f.y, t.x, t.y]


# ---------- Zobrist ----------
static func _zinit_check() -> void:
	if _zinit:
		return
	_zinit = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var z := {}
	for side in 4:
		for t in 8:
			for sq in 18 * 18:
				z["%d:%d:%d" % [side, t, sq]] = rng.randi()
	_zob = z
	_zside = [rng.randi(), rng.randi(), rng.randi(), rng.randi()]


static func _hash(board: Array, side: int) -> int:
	var h: int = _zside[side] if side < _zside.size() else 0
	for r in board.size():
		for c in board[r].size():
			var p = board[r][c]
			if p == null:
				continue
			h ^= int(_zob.get("%d:%d:%d" % [p["side"], p["type"], r * 18 + c], 0))
	return h


# ---------- 估值:子力 + 位置表 ----------
static func _evaluate(board: Array, side: int, perks_red: Dictionary, perks_black: Dictionary) -> float:
	var red := 0.0
	var black := 0.0
	for r in R.ROWS:
		for c in R.COLS:
			var p = board[r][c]
			if p == null:
				continue
			var v := _piece_bonus(r, c, p)
			if p["side"] == R.Side.RED:
				red += v
			else:
				black += v
	var score := red - black
	if side == R.Side.BLACK:
		score = -score
	return score


static func _piece_bonus(r: int, c: int, p) -> float:
	var v: float = VALUES.get(p["type"], 1.0)
	var row: int = r if p["side"] == R.Side.RED else R.ROWS - 1 - r
	var idx: int = row * 9 + c
	var pst: Array = []
	match p["type"]:
		R.Type.PAWN: pst = PST_PAWN
		R.Type.HORSE: pst = PST_HORSE
		R.Type.CANNON: pst = PST_CANNON
		R.Type.ROOK: pst = PST_ROOK
		R.Type.ADVISOR: pst = PST_ADVISOR
		R.Type.ELEPHANT: pst = PST_ELEPHANT
	return v + (pst[idx] if idx < pst.size() else 0.0)


static func _evaluate4(board: Array, side: int, perks4: Array) -> float:
	var score := 0.0
	var center := Vector2(8, 8)
	for r in board.size():
		for c in board[r].size():
			var p = board[r][c]
			if p == null:
				continue
			var v: float = VALUES.get(p["type"], 1.0)
			v += 0.1 * (10.0 - float(Vector2(c, r).distance_to(center)))
			score += v if p["side"] == side else -v
	return score


# ---------- 兜底(原单步贪心) ----------
static func _greedy_fallback(board: Array, side: int, perks_red: Dictionary, perks_black: Dictionary) -> Dictionary:
	var best := {}
	var best_score := -INF
	for r in R.ROWS:
		for c in R.COLS:
			var pos := Vector2i(c, r)
			var p = board[r][c]
			if p == null or p["side"] != side:
				continue
			for t in R.legal_moves(board, pos, perks_red, perks_black):
				var score := _greedy_score(board, pos, t, side, perks_red, perks_black)
				if score > best_score:
					best_score = score
					best = {"from": pos, "to": t}
	return best


static func _greedy_score(board: Array, from: Vector2i, to: Vector2i, side: int, perks_red: Dictionary, perks_black: Dictionary) -> float:
	var res := R.apply_move(board, from, to)
	var captured = res["captured"]
	var score := 0.0
	if captured != null:
		if captured["type"] == R.Type.KING:
			return 100000.0
		var v: float = VALUES.get(captured["type"], 1.0)
		score += v * 10.0 + v * 5.0
	if R.is_in_check(res["board"], 1 - side, perks_red, perks_black):
		score += 6.0
	return score


static func _greedy_fallback4(board: Array, side: int, perks4: Array) -> Dictionary:
	var best := {}
	var best_score := -INF
	for r in board.size():
		for c in board[r].size():
			var pos := Vector2i(c, r)
			var p = board[r][c]
			if p == null or p["side"] != side:
				continue
			for t in R.raw_moves4(board, pos, perks4):
				var res := R.apply_move(board, pos, t)
				var captured = res["captured"]
				var score := 0.0
				if captured != null:
					if captured["type"] == R.Type.KING:
						return {"from": pos, "to": t}
					var v: float = VALUES.get(captured["type"], 1.0)
					score += v * 10.0 + v * 5.0
				if score > best_score:
					best_score = score
					best = {"from": pos, "to": t}
	return best
