# 中国象棋 AI:negamax alpha-beta 搜索 + 迭代加深 + 时间上限 + 吃子排序 + 子力/位置估值
# 借鉴 github.com/pengjiu/ChineseChess 的搜索(NegaScout/剪枝/排序)与估值思路,用现有 chess_rules.gd 数组棋盘实现。
extends RefCounted

const R := preload("res://scripts/chess_rules.gd")

const VALUES := {
	R.Type.KING: 10000.0,
	R.Type.ADVISOR: 2.0,
	R.Type.ELEPHANT: 2.0,
	R.Type.HORSE: 4.0,
	R.Type.ROOK: 9.0,
	R.Type.CANNON: 4.5,
	R.Type.PAWN: 1.0,
	R.Type.QUEEN: 12.0,
}

# 兵/卒过河推进奖励(行 0=对方底线最深,行 9=己方起始)
const PAWN_ADVANCE := {9: 0.0, 8: 0.3, 7: 0.6, 6: 1.0, 5: 1.8, 4: 2.4, 3: 3.0, 2: 3.4, 1: 3.8, 0: 4.2}
# 列中心倾向(3/4/5 列最有利)
const COL_CENTER := [0.0, 0.1, 0.5, 1.0, 1.2, 1.0, 0.5, 0.1, 0.0]
const ROOK_ROW := [0.0, 0.2, 0.4, 0.6, 0.8, 0.6, 0.4, 0.2, 0.0, 0.0]

const TIME_LIMIT_2P := 650  # 毫秒
const TIME_LIMIT_4P := 320
const MAX_DEPTH_2P := 3
const MAX_DEPTH_4P := 2


static func choose_move(board: Array, side: int, perks_red: Dictionary, perks_black: Dictionary) -> Dictionary:
	var deadline := Time.get_ticks_msec() + TIME_LIMIT_2P
	var best := _iterative_deepening(board, side, perks_red, perks_black, MAX_DEPTH_2P, deadline)
	return best if not best.is_empty() else _greedy_fallback(board, side, perks_red, perks_black)


static func choose_move4(board: Array, side: int, perks4: Array) -> Dictionary:
	var deadline := Time.get_ticks_msec() + TIME_LIMIT_4P
	var best := _iterative_deepening4(board, side, perks4, MAX_DEPTH_4P, deadline)
	return best if not best.is_empty() else _greedy_fallback4(board, side, perks4)


# 迭代加深:逐层加深,某一层超时则保留上一层最佳
static func _iterative_deepening(board: Array, side: int, perks_red: Dictionary, perks_black: Dictionary, max_depth: int, deadline: int) -> Dictionary:
	var best := {}
	for depth in range(1, max_depth + 1):
		var alpha := -INF
		var root_best := {}
		var root_score := -INF
		var timed_out := false
		for mv in _ordered_moves(board, side, perks_red, perks_black):
			if Time.get_ticks_msec() > deadline:
				timed_out = true
				break
			var res := R.apply_move(board, mv["from"], mv["to"])
			var score := -_negamax(res["board"], 1 - side, depth - 1, -INF, -alpha, perks_red, perks_black, deadline)
			if score > root_score:
				root_score = score
				root_best = mv
			alpha = maxf(alpha, score)
		if timed_out:
			break
		if not root_best.is_empty():
			best = root_best
	return best


static func _iterative_deepening4(board: Array, side: int, perks4: Array, max_depth: int, deadline: int) -> Dictionary:
	var best := {}
	for depth in range(1, max_depth + 1):
		var root_best := {}
		var root_score := -INF
		var timed_out := false
		for mv in _ordered_moves4(board, side, perks4):
			if Time.get_ticks_msec() > deadline:
				timed_out = true
				break
			var res := R.apply_move(board, mv["from"], mv["to"])
			var score := -_negamax4(res["board"], 1 - side, depth - 1, -INF, -root_score, perks4, deadline)
			if score > root_score:
				root_score = score
				root_best = mv
		if timed_out:
			break
		if not root_best.is_empty():
			best = root_best
	return best


# negamax alpha-beta(2p)。超时返回 0 以尽快返回。
static func _negamax(board: Array, side: int, depth: int, alpha: float, beta: float, perks_red: Dictionary, perks_black: Dictionary, deadline: int) -> float:
	if Time.get_ticks_msec() > deadline:
		return _evaluate(board, side, perks_red, perks_black)
	if depth <= 0:
		return _evaluate(board, side, perks_red, perks_black)
	var moves := _ordered_moves(board, side, perks_red, perks_black)
	if moves.is_empty():
		if R.is_in_check(board, side, perks_red, perks_black):
			return -90000.0 + depth  # 被将死
		return 0.0  # 困毙
	var best := -INF
	var a := alpha
	for mv in moves:
		if Time.get_ticks_msec() > deadline:
			break
		var res := R.apply_move(board, mv["from"], mv["to"])
		var score := -_negamax(res["board"], 1 - side, depth - 1, -beta, -a, perks_red, perks_black, deadline)
		if score > best:
			best = score
		a = maxf(a, score)
		if a >= beta:
			break
	return best


static func _negamax4(board: Array, side: int, depth: int, alpha: float, beta: float, perks4: Array, deadline: int) -> float:
	if Time.get_ticks_msec() > deadline:
		return _evaluate4(board, side, perks4)
	if depth <= 0:
		return _evaluate4(board, side, perks4)
	var moves := _ordered_moves4(board, side, perks4)
	if moves.is_empty():
		return -90000.0 + depth
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


# 生成着法,吃子优先排序(简化历史启发式)
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
					s = 100.0 + VALUES.get(cap["type"], 1.0)
				moves.append({"from": pos, "to": t, "score": s})
	moves.sort_custom(func(a, b): return a["score"] > b["score"])
	return moves


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
					s = 100.0 + VALUES.get(cap["type"], 1.0)
				moves.append({"from": pos, "to": t, "score": s})
	moves.sort_custom(func(a, b): return a["score"] > b["score"])
	return moves


# 估值:子力 + 位置(过河兵/中心马炮车/车中行),站在 side 视角
static func _evaluate(board: Array, side: int, perks_red: Dictionary, perks_black: Dictionary) -> float:
	var red := 0.0
	var black := 0.0
	for r in R.ROWS:
		for c in R.COLS:
			var p = board[r][c]
			if p == null:
				continue
			var v: float = VALUES.get(p["type"], 1.0)
			if p["type"] == R.Type.PAWN:
				v += PAWN_ADVANCE.get(r, 0.0)
			elif p["type"] == R.Type.HORSE or p["type"] == R.Type.CANNON:
				v += COL_CENTER[c] * 0.6
			elif p["type"] == R.Type.ROOK:
				v += COL_CENTER[c] * 0.5 + ROOK_ROW[r] * 0.8
			if p["side"] == R.Side.RED:
				red += v
			else:
				black += v
	var score := red - black
	if side == R.Side.BLACK:
		score = -score
	if R.is_in_check(board, side, perks_red, perks_black):
		score -= 8.0
	return score


static func _evaluate4(board: Array, side: int, perks4: Array) -> float:
	var score := 0.0
	var center := Vector2(8, 8)
	for r in board.size():
		for c in board[r].size():
			var p = board[r][c]
			if p == null:
				continue
			var v: float = VALUES.get(p["type"], 1.0)
			if p["side"] == side:
				score += v
				score += 0.1 * (10.0 - float(Vector2(c, r).distance_to(center)))
			else:
				score -= v
	return score


# 兜底:原单步贪心(搜索失败时用)
static func _greedy_fallback(board: Array, side: int, perks_red: Dictionary, perks_black: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
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
				score += rng.randf_range(-0.5, 0.5)
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
	var center := Vector2i(4, 5)
	score += 0.1 * (10.0 - float((to - center).length()))
	return score


static func _greedy_fallback4(board: Array, side: int, perks4: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var best := {}
	var best_score := -INF
	for r in board.size():
		for c in board[r].size():
			var pos := Vector2i(c, r)
			var p = board[r][c]
			if p == null or p["side"] != side:
				continue
			for t in R.raw_moves4(board, pos, perks4):
				var score := _greedy_score4(board, pos, t, side, perks4)
				score += rng.randf_range(-0.5, 0.5)
				if score > best_score:
					best_score = score
					best = {"from": pos, "to": t}
	return best


static func _greedy_score4(board: Array, from: Vector2i, to: Vector2i, side: int, perks4: Array) -> float:
	var res := R.apply_move(board, from, to)
	var captured = res["captured"]
	var score := 0.0
	if captured != null:
		if captured["type"] == R.Type.KING:
			return 100000.0
		var v: float = VALUES.get(captured["type"], 1.0)
		score += v * 10.0 + v * 5.0
	var center := Vector2i(8, 8)
	score += 0.1 * (10.0 - float((to - center).length()))
	return score
