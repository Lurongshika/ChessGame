# 简单贪心 AI:按吃子价值 + 将军 + 中心控制评分
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
}


static func choose_move(board: Array, side: int, perks_red: Dictionary, perks_black: Dictionary) -> Dictionary:
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
				var score := _score_move(board, pos, t, side, perks_red, perks_black)
				score += rng.randf_range(-0.5, 0.5)
				if score > best_score:
					best_score = score
					best = {"from": pos, "to": t}
	return best


static func _score_move(board: Array, from: Vector2i, to: Vector2i, side: int, perks_red: Dictionary, perks_black: Dictionary) -> float:
	var res := R.apply_move(board, from, to)
	var nb: Array = res["board"]
	var captured = res["captured"]
	var score := 0.0
	if captured != null:
		if captured["type"] == R.Type.KING:
			return 100000.0
		var v: float = VALUES[captured["type"]]
		score += v * 10.0  # 吃掉的价值
		score += v * 5.0   # 对方损失的价值
	# 将军加分
	if R.is_in_check(nb, 1 - side, perks_red, perks_black):
		score += 6.0
	# 轻微中心倾向
	var center := Vector2i(4, 5)
	score += 0.1 * (10.0 - float((to - center).length()))
	return score
