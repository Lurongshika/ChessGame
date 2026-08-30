# 秘弈:对局场景(渲染 + 交互 + 状态机)
extends Node2D

const R := preload("res://scripts/chess_rules.gd")
const Perks := preload("res://scripts/perks.gd")
const AI := preload("res://scripts/ai.gd")
const FloatingPanel := preload("res://scripts/floating_panel.gd")
const PerkCard := preload("res://scripts/perk_card.gd")
const Profile := preload("res://scripts/profile_util.gd")
const BgLayer := preload("res://scripts/bg_layer.gd")
const ChatPanel := preload("res://scripts/chat_panel.gd")

const CELL := 56
# 棋盘在 1280×720 窗口中直接居中:中心 x=(1280-504)/2=388,中心 y=(720-560)/2=80
const ORIGIN := Vector2(388, 80)
# 9 列 10 行的棋盘:竖线 9 条(8 个间距)、横线 10 条(9 个间距)
const BOARD_W := (R.COLS - 1) * CELL
const BOARD_H := (R.ROWS - 1) * CELL

enum Phase { DRAFT, SKILL_DRAFT, PLAY, OVER }

# --- 对局状态 ---
var board: Array = []
var perks_red := {}
var perks_black := {}
var turn := R.Side.RED
var phase := Phase.DRAFT
var winner := -1
var four_mode := false          # 四人模式:走子/渲染/状态机走复制分支
var alive4 := {0: true, 1: true, 2: true, 3: true}
var turn4 := 0                  # 四人:当前方(SIDE_ORDER4 索引)
var winner4 := -1
var selected4 := Vector2i(-1, -1)
var moves4: Array = []
var in_check := false

# --- 技能选择(开局 3 次三选一) ---
var draft_side := R.Side.RED
var draft_round := 0
var draft_options: Array = []
var draft_red_done := false    # 联机:红方(主机)是否已选完
var draft_black_done := false  # 联机:黑方(客户端)是否已选完

# --- 主动技能系统 ---
var skill_cd := {0: {}, 1: {}}      # side -> perk_id -> 剩余冷却回合
var captured_history: Array = []    # 被吃子记录 {side, type, pos, birth_pos}
var revive_count := {0: 0, 1: 0}    # 生生不息:已累计被吃数
var queen_charge := {0: 0, 1: 0}   # 皇后:被吃充能(己方每被吃 1 子 +1,上限 3)
var extra_move := {0: false, 1: false}   # 命运之轮:下回合额外行动一次
var hermit_pending := false     # 隐者:已释放,下回合移动的子隐身
var hermit_active := false      # 隐者:本回合移动的子隐身
var controlled_piece := {}      # 倒吊人:{"pos": Vector2i, "owner": side} 获得控制权的对方棋子
var disabled_skills := {0: "", 1: ""}  # 审判:每回合被禁用的敌方主动技能
var last_eat := {"side": -1, "type": -1}  # 恶魔:上次吃子方与类型(禁同类型连续吃)
var emo2_turns := {0: 0, 1: 0}  # 恶魔逆位:被吃方剩余免疫回合数
var emo2_type := {0: -1, 1: -1}  # 恶魔逆位:被吃方的"吃它类型"(该类型可再吃,其他类型免疫)
var all_hidden_turns := {0: 0, 1: 0}  # 隐者(进阶):全员隐身剩余回合数
var hidden_turns := {}                # 隐者(普通):指定棋子剩余隐身回合数 -> {pos: 剩余}
var skip_next_turn := {0: false, 1: false}  # 节制(进阶):下回合被跳过
var invincible_piece := Vector2i(-1, -1)  # 皇帝:指定无敌的己方棋子
var invincible_piece_side := -1    # 皇帝:无敌棋子所属方(用于"己方移动后清除")
var invincible_piece_turns := 0    # 皇帝:无敌剩余回合数(移动后递减)
var counter_side := -1          # 皇后(进阶):反制方(该方棋子被吃时同归于尽)
var siwang_charge := {0: 0, 1: 0}  # 死亡:被吃充能(己方每被吃 1 子 +1)
var lianren2_charge := {0: 0, 1: 0}  # 恋人逆位:被吃充能(需求2,使用后其他技能完成冷却/充能)
var sync_pieces: Array = []     # 命运之轮(进阶):协同棋子(移动不消耗步数,每子每回合一次)
var _sync_moved: Array[Vector2i] = []  # 命运之轮(进阶):本回合已免费移动过的协同棋子(防无限移动)
var star2_charge := {0: 0, 1: 0}  # 星星逆位:蓄势(每蓄势可免费移动一个兵)
var controlled_turns := 0       # 倒吊人:控制权剩余回合数
var controlled_all_turns := 0   # 倒吊人逆位:全棋子控制剩余回合数(释放后跳过本回合,下回合起生效)
var controlled_all_owner := -1  # 倒吊人逆位:全棋子控制权归属方
var _controlled_moved: Array[Vector2i] = []  # 倒吊人逆位:本回合已移动的对方棋子
var control_foreign := {0: false, 1: false}  # 倒吊人(正位):该方是否处于"只能操控非己方棋子"模式
var pope_guarded := {}          # 教皇:象 5×5 范围内己方棋子(获得无敌) -> {pos: true}
var pope_countered := {}        # 教皇逆位:象 5×5 范围内的子(获得反制) -> {pos: true}
var undo_snapshot := {}         # 图鉴演示:悔棋前完整状态快照(供撤销悔棋)
var extra_turn := {0: false, 1: false}  # 节制:下回合追加行动
var suicide_mark := {}              # 皇帝:{pos: side} 被吃时同归于尽
var hidden_pieces := {}             # 隐者:{pos: side}
var invincible_side := -1           # 皇后:无敌方
var invincible_side_turns := 0      # 皇后:无敌剩余回合数(移动后递减)
var targeting := {}                 # 目标选择状态 {"perk", "side", "stage", "data"}

# --- 四人模式技能系统(复制双人逻辑,独立状态) ---
var perks4 := {0: {}, 1: {}, 2: {}, 3: {}}  # side -> {perk_id: true}
var skill_cd4 := {0: {}, 1: {}, 2: {}, 3: {}}
var captured_history4: Array = []
var revive_count4 := {0: 0, 1: 0, 2: 0, 3: 0}
var queen_charge4 := {0: 0, 1: 0, 2: 0, 3: 0}
var extra_move4 := {0: false, 1: false, 2: false, 3: false}
var hermit_pending4 := false
var hermit_active4 := false
var controlled_piece4 := {}
var disabled_skills4 := {0: "", 1: "", 2: "", 3: ""}
var last_eat4 := {"side": -1, "type": -1}
var emo2_turns4 := {0: 0, 1: 0, 2: 0, 3: 0}  # 四人:恶魔逆位被吃方免疫剩余回合
var emo2_type4 := {0: -1, 1: -1, 2: -1, 3: -1}  # 四人:恶魔逆位被吃方的"吃它类型"
var all_hidden_turns4 := {0: 0, 1: 0, 2: 0, 3: 0}
var hidden_turns4 := {}                # 四人:隐者(普通)指定棋子剩余隐身回合数 -> {pos: 剩余}
var skip_next_turn4 := {0: false, 1: false, 2: false, 3: false}
var invincible_piece4 := Vector2i(-1, -1)
var invincible_piece_side4 := -1  # 四人:皇帝无敌棋子所属方(用于"己方移动后清除")
var invincible_piece_turns4 := 0  # 四人:皇帝无敌剩余回合数
var counter_side4 := -1
var siwang_charge4 := {0: 0, 1: 0, 2: 0, 3: 0}
var lianren2_charge4 := {0: 0, 1: 0, 2: 0, 3: 0}  # 四人:恋人逆位被吃充能(需求2)
var star2_charge4 := {0: 0, 1: 0, 2: 0, 3: 0}  # 四人:星星逆位蓄势
var sync_pieces4: Array = []
var _sync_moved4: Array[Vector2i] = []  # 四人:协同棋子本回合已免费移动(每回合一次,防无限移动)
var controlled_turns4 := 0
var controlled_all_turns4 := 0   # 四人:倒吊人逆位全棋子控制剩余回合数
var controlled_all_owner4 := -1  # 四人:全棋子控制权归属方
var _controlled_moved4: Array[Vector2i] = []  # 四人:本回合已移动的对方棋子
var control_foreign4 := {0: false, 1: false, 2: false, 3: false}  # 四人:倒吊人(正位)操控非己方棋子模式
var pope_guarded4 := {}
var pope_countered4 := {}       # 四人:教皇逆位象 5×5 范围内的子(获得反制)
var extra_turn4 := {0: false, 1: false, 2: false, 3: false}
var suicide_mark4 := {}
var hidden_pieces4 := {}
var invincible_side4 := -1
var invincible_side_turns4 := 0  # 四人:皇后无敌剩余回合数
var targeting4 := {}
var actions_left4 := 1
var first_moved4 := Vector2i(-1, -1)
var free_retreat4_targets: Array[Vector2i] = []  # 四人:星星免费移兵落位(蓝色,不消耗行动)
var free_retreat4_used := false                   # 四人:星星正位每回合一次
var draft4_side := 0        # 四人 DRAFT:当前选技能方
var kill_count4 := {0: 0, 1: 0, 2: 0, 3: 0}  # 四人杀棋计数
var grey_side4 := -1           # 将帅被杀后变灰保留的方(-1=无)
var in_check4 := {0: false, 1: false, 2: false, 3: false}  # 四人:各方王是否被将
var _prev_check4 := {0: false, 1: false, 2: false, 3: false}  # 四人:上一次被将(用于上升沿警报)
var draft4_round := 0
var draft4_options: Array = []
var _draft_selected4: Array = []  # 四人 DRAFT:当前方已点选的技能(最多 3 个)
var _four_draft_groups: Array = []  # 本地四人:四组 8 选 3 候选
var draft4_done := {0: false, 1: false, 2: false, 3: false}
var my_side4 := -1            # 联机四人:客户端自己的方(0-3)
var four_ready_count := 0     # 联机四人:主机收到 client_ready 数量
var four_draft_picks := {0: [], 1: [], 2: [], 3: []}  # 联机四人:每方选出的技能
var four_side_to_peer := {}   # 联机四人:side -> peer_id(host 用)
var _four_draft_started := false
var _four_ready_done := {}    # 联机四人:已发 client_ready 的 pid
var _reconnecting := false    # 断线重连中
var _four_side_absent := {}  # 四人主机:断线待重连的 side -> true
var _reconnect_timer := 0.0
var _reconnect_interval := 2.0

# --- 网络 ---

var net_role := "local"   # "local" / "host"(红方) / "client"(黑方)
var own_side := -1
var client_peer_id := 0

var selected := Vector2i(-1, -1)
var moves_cache: Array[Vector2i] = []
var free_retreat_targets: Array[Vector2i] = []
var free_elephant_targets: Array[Vector2i] = []  # 月亮逆位:象免费落位(蓝色,不消耗步数)

var actions_left := 1
var first_moved := Vector2i(-1, -1)
var free_retreat_used := false
var turn_counts := {0: 0, 1: 0}  # 双方各自已进行的回合数
var ai_busy := false

# 黑方客户端视角:棋盘上下翻转,让自己(黑方)显示在下方
var flip_board := false

# --- 存档与复盘 ---
const SLOT_COUNT := 3
var current_slot := 1
var move_history: Array = []   # [{from: Vector2i, to: Vector2i, kind: String}]
var initial_snapshot := {}     # {board, perks_red, perks_black} 开局快照
var replay_mode := false
var replay_index := 0
var replay_board: Array = []
var replay_auto := false
var replay_timer := 0.0
var replay_root: Control
var replay_label: Label

# --- UI ---
var ui: CanvasLayer
var status_label: Label
var move_log_box: VBoxContainer
var _record4_history: Array = []  # 四人:对局记录 [{text, turn}]
var self_panel: FloatingPanel
var enemy_panel: FloatingPanel
var self_perk_list_box: VBoxContainer
var enemy_perk_list_box: VBoxContainer
var _four_perk_boxes: Array = []  # 四人模式:四方技能悬浮窗内容框
var draft_root: Control
var _draft_ui_shown := false  # 三选一界面是否已首次显示(首次弹入,刷新重建不重复)
var result_root: Control
var four_result_root: Control  # 四人:结算遮罩(返回大厅)
var net_wait_label: Label
var chat: Panel  # 对局聊天栏
var record_panel: Panel  # 对局记录中心悬浮窗
var record_btn: Button  # 屏幕下方对局记录按钮
var record_box: VBoxContainer
var record_visible := false
var _lobby_ready_done := false  # 大厅→对局:客户端已进入 game 场景(防重复开局)

# 玩家徽章(左下我方 / 右上敌方)
var my_badge_icon: TextureRect
var my_badge_name: Label
var enemy_badge_icon: TextureRect
var enemy_badge_name: Label
var my_badge_frame: Panel
var enemy_badge_frame: Panel
var _glow_time := 0.0
var _status4_until := 0.0   # 四人:状态提示显示到此刻(秒),之后恢复回合显示
var _four_frames: Array = []  # 四人:四方头像框 {frame, side}
var _four_mode_label: Label  # 左上角当前模式
var _progress_labels4 := {}  # 右上角进度: side -> Label
var _my_turn_breath4 := false  # 自己回合呼吸显示
var _move_anims: Array = []  # 四人:棋子移动动画 [{piece, from_px, to_px, t, dur}]
var _debris: Array = []     # 吃子破碎粒子 [{pos, vel, life, max, size, color}]
var _shake_time := 0.0      # 屏幕震动剩余时间
var _shake_strength := 0.0  # 屏幕震动强度
var my_info := {}
var enemy_info := {}

# 从 perks.txt 加载的技能池 { id: {name, desc, cat} }
var perks_data := {}


func _ready() -> void:
	get_window().title = "秘弈"
	perks_data = Perks.load_perks(Global.perk_pool)
	net_role = Global.net_role
	four_mode = Global.game_mode == "four"
	if four_mode:
		# 联机四人:每个进程各控一方(不强制 local),side 由大厅分配
		if Global.from_lobby:
			if Global.reconnect_mode:
				# 断线重连:跳过席位自查(进程重启无 lobby_players),等主机 sync_state4 告知 side
				net_role = "client"
			else:
				my_side4 = _find_my_side4()
				if my_side4 >= 0:
					own_side = my_side4
				if net_role == "host":
					_build_four_side_map()
				# 本机视角旋转:自己的半场朝下(红不转/黑180°/绿90°CW/蓝270°CW)
				_view_rot4 = {0: 0, 1: 1, 2: 2, 3: 3}.get(my_side4, 0)
				# 客户端:持久化重连信息(进程崩溃重启后可一键重连)
				if net_role == "client":
					Global.save_reconnect_info()
		else:
			net_role = "local"
	if four_mode:
		# 四人联机:own_side 已由 my_side4 决定,不覆盖
		pass
	elif net_role == "host":
		own_side = R.Side.RED
	elif net_role == "client":
		if own_side < 0:
			own_side = R.Side.BLACK
			flip_board = true  # 黑方客户端棋盘反转
	_build_ui()
	if four_mode:
		# 四人模式:复制双人技能流程(开局四方各三选一) + 独立走子/渲染分支
		board = R.make_board4()
		turn4 = 0
		alive4 = {0: true, 1: true, 2: true, 3: true}
		winner4 = -1
		selected4 = Vector2i(-1, -1)
		moves4 = []
		if Global.reconnect_mode:
			# 断线重连:进程重启后直接重连主机,等待分配席位并回传状态(跳过 Lobby 避免跨场景 RPC 路径错误)
			net_role = "client"
			_reconnecting = true
			net_wait_label = _make_label("正在重连对局...", 26, Color(0.95, 0.85, 0.6))
			net_wait_label.position = Vector2(0, 200)
			net_wait_label.size = Vector2(1280, 120)
			net_wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ui.add_child(net_wait_label)
			_setup_client()
			return
		if Global.from_lobby and net_role != "local":
			_from_lobby_start4()
		elif Global.standard_mode:
			_start_four_game()
		else:
			_show_skill_draft4()
			if _has_user_arg("--auto"):
				call_deferred("_auto_pick_four")
		return
	if net_role == "local":
		if Global.demo_perk != "":
			# 图鉴演示对局:玩家(红方)拥有当前查看的技能,机器人(黑方)无技能,直接开局
			Global.game_mode = "ai"
			perks_red = {Global.demo_perk: true}
			perks_black = {}
			phase = Phase.PLAY
			_setup_board()
			_snapshot_initial()
			_begin_turn()
			_set_demo_hint()
			return
		elif Global.load_slot > 0 and _load_game(Global.load_slot):
			Global.load_slot = 0
			phase = Phase.PLAY
			_refresh_move_log()
			_update_ui()
			queue_redraw()
			_maybe_ai()
			return
		if Global.standard_mode:
			# 标准模式:双方不使用任何技能,直接开局
			perks_red = {}
			perks_black = {}
			_start_game()
		else:
			_show_skill_draft()
	else:
		if Global.from_lobby:
			# 从大厅进入:连接已建立,复用,不重复建房/连接
			_from_lobby_start()
		else:
			_show_net_wait()


# ==================== UI 构建 ====================

func _build_ui() -> void:
	# 背景 shader 层(在最底层,棋盘之下)
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	var bg := BgLayer.new()
	bg_layer.add_child(bg)

	ui = CanvasLayer.new()
	add_child(ui)

	status_label = _make_label("", 24, Color(1, 0.95, 0.85))
	status_label.position = Vector2(0, 10)
	status_label.size = Vector2(1280, 36)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(status_label)

	# 联机对局聊天栏(左下角;本地模式不显示)
	if Global.net_role != "local":
		chat = ChatPanel.new()
		chat.setup(_font(), _send_chat_game, _chat_tab_complete)
		ui.add_child(chat)

	if four_mode:
		_build_ui4()
		return

	_build_player_badges()

	var title_label := _make_label("秘弈", 30, Color(0.95, 0.85, 0.6))
	title_label.position = Vector2(20, 14)
	title_label.size = Vector2(300, 40)
	ui.add_child(title_label)

	# 对局记录:屏幕中心半透明悬浮窗(默认隐藏,下方按钮切换)
	_build_record_panel()

	# 浮动技能面板:可拖动/折叠/缩放,交互与系统窗口一致(先设位置尺寸再 setup)
	# 我方技能悬浮框(上)——下移给右上角敌方徽章让位
	self_panel = FloatingPanel.new()
	self_panel.position = Vector2(1030, 96)
	self_panel.size = Vector2(230, 290)
	self_panel.setup("我方技能", _font())
	ui.add_child(self_panel)

	self_perk_list_box = _make_scroll_list(self_panel)

	# 敌方技能悬浮框(下)
	enemy_panel = FloatingPanel.new()
	enemy_panel.position = Vector2(1030, 402)
	enemy_panel.size = Vector2(230, 290)
	enemy_panel.setup("敌方技能", _font())
	ui.add_child(enemy_panel)

	enemy_perk_list_box = _make_scroll_list(enemy_panel)

	# 退出对局按钮:固定在游戏窗口右下角
	# 图鉴演示对局:悔棋 / 撤销悔棋(右上角,退出按钮左侧)
	if Global.demo_perk != "":
		var undo_btn := _make_button("悔棋", Vector2(1280 - 224 - 12 - 110 - 8 - 100 - 8, 720 - 44 - 12), Vector2(100, 44))
		undo_btn.pressed.connect(_do_undo)
		ui.add_child(undo_btn)
		var redo_btn := _make_button("撤销悔棋", Vector2(1280 - 224 - 12 - 110 - 8, 720 - 44 - 12), Vector2(110, 44))
		redo_btn.pressed.connect(_do_redo)
		ui.add_child(redo_btn)
	var quit_btn := _make_button("退出对局", Vector2(1280 - 224 - 12, 720 - 44 - 12), Vector2(224, 44))
	quit_btn.pressed.connect(func():
		if Global.demo_perk != "":
			Global.demo_perk = ""
			Global.change_scene_with_fade("res://scenes/manual.tscn")
		else:
			Global.change_scene_with_fade("res://scenes/main.tscn")
	)
	ui.add_child(quit_btn)

	# 悔棋按钮(仅普通人机对局;图鉴演示对局用右上角"悔棋/撤销悔棋"双按钮)
	if Global.game_mode == "ai" and Global.demo_perk == "":
		var undo_btn := _make_button("悔棋", Vector2(1280 - 224 * 2 - 24, 720 - 44 - 12), Vector2(224, 44))
		undo_btn.pressed.connect(_undo_ai_move)
		ui.add_child(undo_btn)



	# 左上角游戏标题
# 对局记录:屏幕中心半透明悬浮窗 + 下方"对局记录"按钮(按一下显示/隐藏)
func _build_record_panel() -> void:
	record_panel = Panel.new()
	record_panel.position = Vector2(1280 / 2 - 260, 720 / 2 - 180)
	record_panel.size = Vector2(520, 360)
	record_panel.visible = false
	var rbg := StyleBoxFlat.new()
	rbg.bg_color = Color(0.1, 0.12, 0.18, 0.88)
	rbg.set_corner_radius_all(10)
	rbg.border_color = Color(0.5, 0.45, 0.35)
	rbg.set_border_width_all(2)
	record_panel.add_theme_stylebox_override("panel", rbg)
	ui.add_child(record_panel)

	var rtitle := _make_label("对局记录", 20, Color(0.95, 0.85, 0.6))
	rtitle.position = Vector2(16, 8)
	rtitle.size = Vector2(200, 28)
	record_panel.add_child(rtitle)

	var rclose := _make_button("关闭", Vector2(520 - 70, 6), Vector2(60, 30))
	rclose.pressed.connect(_toggle_record)
	record_panel.add_child(rclose)

	var rscroll := ScrollContainer.new()
	rscroll.position = Vector2(16, 44)
	rscroll.size = Vector2(520 - 32, 360 - 52)
	rscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	record_panel.add_child(rscroll)
	record_box = VBoxContainer.new()
	record_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	record_box.add_theme_constant_override("separation", 3)
	rscroll.add_child(record_box)

	# 屏幕中心正下方按钮
	record_btn = _make_button("对局记录", Vector2(1280 / 2 - 70, 720 - 48), Vector2(140, 40))
	record_btn.pressed.connect(_toggle_record)
	ui.add_child(record_btn)
	# 按钮置顶,不被聊天遮挡
	record_btn.z_index = 10


func _toggle_record() -> void:
	record_visible = not record_visible
	if record_panel == null:
		return
	if record_visible:
		record_panel.visible = true
		Global.pop_in(record_panel)
	else:
		Global.pop_out(record_panel, 0.25, func(): record_panel.visible = false)


# 当前模式名(左上角)
func _mode_name4() -> String:
	if Global.standard_mode:
		return "标准模式"
	var win_mode: String = Global.game_rules.get("win_mode", "classic")
	match win_mode:
		"occupy":
			return "占领模式"
		"kills":
			return "击杀模式(目标 %d)" % int(Global.game_rules.get("kill_count", 2))
	return "技能模式"


# 右上角 2×2 胜利进度面板
func _build_progress_panel4() -> void:
	# 棋盘正下方一排:四方胜利进度横排(不与右上角头像重叠)
	var panel := Panel.new()
	var pwidth := 560
	var px := (1280 - pwidth) / 2
	var py := 632  # 棋盘下边缘 615 之下
	panel.position = Vector2(px, py)
	panel.size = Vector2(pwidth, 34)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.12, 0.16, 0.7)
	sb.set_corner_radius_all(8)
	sb.border_color = Color(0.45, 0.4, 0.32)
	sb.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", sb)
	ui.add_child(panel)
	# 一排 4 格:黑(1)红(0)绿(2)蓝(3)
	var cell_w := 128
	var order := [1, 0, 2, 3]
	for i in order.size():
		var side: int = order[i]
		var cx := 8 + i * (cell_w + 8)
		var color_dot := ColorRect.new()
		color_dot.color = _side_color(side)
		color_dot.position = Vector2(cx, 9)
		color_dot.size = Vector2(14, 14)
		panel.add_child(color_dot)
		var l := _make_label("", 12, Color(0.9, 0.9, 0.85))
		l.position = Vector2(cx + 20, 8)
		l.size = Vector2(cell_w - 22, 18)
		l.add_theme_font_size_override("font_size", 12)
		panel.add_child(l)
		_progress_labels4[side] = l
	_update_progress4()


# 刷新四方胜利进度
func _update_progress4() -> void:
	if _progress_labels4.is_empty():
		return
	# 同步左上角模式名
	if _four_mode_label != null:
		_four_mode_label.text = _mode_name4()
	var win_mode: String = Global.game_rules.get("win_mode", "classic")
	for side in _progress_labels4:
		var l: Label = _progress_labels4[side]
		if win_mode == "occupy":
			var n := 0
			if not board.is_empty():
				for spot in _occupy_spots4():
					var p = board[spot.y][spot.x]
					if p != null and p["side"] == side:
						n += 1
			l.text = "占点 %d/3" % n
		elif win_mode == "kills":
			var target := int(Global.game_rules.get("kill_count", 2))
			l.text = "击杀 %d/%d" % [kill_count4[side], target]
		else:
			l.text = "存活"


func _build_ui4() -> void:
	# 四人模式:不构建对局记录/玩家徽章/双人技能面板,改为四悬浮窗(四方技能)
	# 左上角:当前模式名
	_four_mode_label = _make_label(_mode_name4(), 26, Color(0.95, 0.85, 0.6))
	_four_mode_label.position = Vector2(16, 6)
	_four_mode_label.size = Vector2(340, 36)
	ui.add_child(_four_mode_label)
	# 右上角:胜利进度面板(2×2 四方)
	_build_progress_panel4()
	_four_perk_boxes = []
	# 四角:四位玩家头像+名字+id(轮到走子发光);放独立高层 CanvasLayer,不被 DRAFT/结算遮挡
	var corner_layer := CanvasLayer.new()
	corner_layer.layer = 5
	add_child(corner_layer)
	_four_frames = []
	var corners := {1: Vector2(24, 60), 3: Vector2(1280 - 24 - 240, 60), 0: Vector2(24, 720 - 16 - 66), 2: Vector2(1280 - 24 - 240, 720 - 16 - 66)}
	var id_order := {1: 1, 0: 2, 2: 3, 3: 4}  # 四方 id(黑1 红2 绿3 蓝4)
	for side in [1, 0, 2, 3]:
		var pos: Vector2 = corners[side]
		var info: Dictionary = Global.lobby_players.get(side, {})
		var nm_text: String = info.get("name", SIDE_NAMES4[side])
		var frame := _make_badge_frame(pos)
		corner_layer.add_child(frame)
		# 头像(若有网络头像)
		var icon := TextureRect.new()
		icon.position = Vector2(3, 3)
		icon.size = Vector2(48, 48)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tex: Texture2D = _net_avatar4(info.get("avatar_data", {}), 48)
		if tex != null:
			icon.texture = tex
		frame.add_child(icon)
		# 玩家名称标注(取代上下左右小字;头像下方不再重复显示)
		var idlab := _make_label(nm_text, 12, Color(0.9, 0.9, 0.85))
		idlab.position = pos + Vector2(54, 5)
		idlab.size = Vector2(190, 18)
		idlab.add_theme_font_size_override("font_size", 12)
		idlab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		corner_layer.add_child(idlab)
		_four_frames.append({"frame": frame, "side": side})
	# 按半场位置:上(黑)左上、下(红)左下、左(绿)右上、右(蓝)右下
	var positions := {1: Vector2(20, 90), 0: Vector2(20, 430), 2: Vector2(1030, 90), 3: Vector2(1030, 430)}
	for side in [1, 0, 2, 3]:
		var p := FloatingPanel.new()
		p.position = positions[side]
		p.size = Vector2(230, 280)
		# 悬浮窗标题:玩家名+技能(无大厅数据时用方位名)
		var owner_name: String = ""
		if Global.lobby_players.has(side):
			owner_name = Global.lobby_players[side].get("name", "")
		if owner_name.is_empty():
			owner_name = SIDE_NAMES4[side]
		p.setup(owner_name + "技能", _font())
		ui.add_child(p)
		_four_perk_boxes.append(_make_scroll_list(p))
	_refresh_perk_panels4()
	# 对局记录中心悬浮窗 + 下方按钮
	_build_record_panel()
	# 返回菜单按钮
	var quit_btn := _make_button("返回菜单", Vector2(1280 - 224 - 12, 720 - 44 - 12), Vector2(224, 44))
	quit_btn.pressed.connect(func():
		Global.clear_reconnect_info()
		Global.change_scene_with_fade("res://scenes/main.tscn")
	)
	ui.add_child(quit_btn)


func _refresh_perk_panels4() -> void:
	# 四方技能面板:显示当前方真实技能卡(可点击释放)
	var sides := [1, 0, 2, 3]  # 与 _build_ui4 面板顺序一致(上黑/下红/左绿/右蓝)
	for i in _four_perk_boxes.size():
		if _four_perk_boxes[i] == null:
			continue
		var box: VBoxContainer = _four_perk_boxes[i]
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
		var side: int = sides[i]
		if perks4[side].is_empty():
			var l := _make_label("无技能", 13, Color(0.6, 0.58, 0.54))
			box.add_child(l)
			continue
		for id in perks4[side]:
			# 跳过内部标记键(正义逆位的炮隔子标记不是真实技能)
			if str(id).begins_with("_"):
				continue
			var info: Dictionary = perks_data[id]
			var tip: String = info.get("tip", "")
			# 充能进度:皇后/死亡用充能值(逆位力量可累计至3倍上限),星星逆位显示蓄势,主动技能显示剩余冷却
			var prog := ""
			if id == "huanghou":
				var qcap4 := 3 if perks4[side].has("liliang2") else 1
				prog = "充能 %d/%d" % [queen_charge4[side], qcap4]
			elif id == "siwang":
				var scap4 := 9 if perks4[side].has("liliang2") else 3
				prog = "充能 %d/%d" % [siwang_charge4[side], scap4]
			elif id == "lianren2":
				prog = "充能 %d/2" % lianren2_charge4[side]
			elif id == "xingxing2":
				prog = "蓄势 %d" % star2_charge4.get(side, 0)
			if _is_active_skill(id) and prog.is_empty():
				var cd_left4: int = int(skill_cd4.get(side, {}).get(id, 0))
				if cd_left4 > 0:
					prog = "冷却 %d" % cd_left4
			if not prog.is_empty():
				tip += "  [%s]" % prog
			var card := PerkCard.new()
			card.setup(id, side, info["name"], tip, info["desc"], _font(), true, 200.0)
			# 四人:技能卡背景用该方玩家颜色
			card.bg_tint = _side_color(side)
			card._refresh_style(true, 200.0)
			card.clicked.connect(_on_perk_clicked4)
			box.add_child(card)


func _on_perk_clicked4(perk_id: String, side: int) -> void:
	if phase != Phase.PLAY or winner4 >= 0:
		return
	var cur := current_side4()
	if side != cur:
		_show_status4("只能使用己方(%s)技能" % SIDE_NAMES4[side])
		return
	if not _is_active_skill(perk_id):
		_show_status4("[%s] 被动技能,整局自动生效" % perks_data[perk_id]["name"])
		return
	if actions_left4 < _turn_action_cap4():
		_show_status4("本回合已落子,技能与落子二选一")
		return
	if disabled_skills4[side] == perk_id:
		_show_status4("[%s] 被审判禁用,本回合不可使用" % perks_data[perk_id]["name"])
		return
	var cd: int = skill_cd4[side].get(perk_id, 0)
	if cd > 0:
		_show_status4("[%s] 冷却中(剩余 %d 回合)" % [perks_data[perk_id]["name"], cd])
		return
	if perk_id == "huanghou" and queen_charge4[side] <= 0:
		_show_status4("[皇后] 充能中:己方每被吃 1 子充能 1 点")
		return
	if perk_id == "siwang" and siwang_charge4[side] <= 0:
		_show_status4("[死亡] 充能中:己方每被吃 1 子充能 1 点")
		return
	if net_role != "local" and Global.from_lobby:
		if net_role == "host":
			_execute_skill4(perk_id, side, {})
			_broadcast_state4()
		else:
			# 目标型技能:本地选目标后上报);非目标型直接请求
			if _is_targeting_skill(perk_id):
				_activate_skill4(perk_id, side)
				targeting4["net"] = true
			else:
				request_skill4.rpc_id(1, perk_id, {})
				_show_status4("[%s] 技能已发送" % perks_data[perk_id]["name"])
		return
	_activate_skill4(perk_id, side)


# 四人主动技能执行:复制双人 _activate_skill 的分支
func _activate_skill4(perk_id: String, side: int) -> void:
	_record_skill4(side, perk_id)
	# 目标型技能:进入选目标阶段,不立即提醒(选完目标执行时才提醒,见各 _handle_*_target4)
	var is_targeting_now4: bool = _is_targeting_skill(perk_id)
	if not is_targeting_now4:
		# 全局释放提醒(屏幕中央)
		_show_skill_announce(perk_id, side)
	match perk_id:
		"nvjisi", "nvjisi2":
			_skill_priestess4(perk_id, side)
		"yuzhe", "yuzhe2":
			_skill_fool4(perk_id, side)
		"jiezhi", "jiezhi2":
			_skill_temperance4(perk_id, side)
		"huanghou", "huanghou2":
			_skill_queen4(perk_id, side)
		"mingyun", "mingyun2":
			_skill_wheel4(perk_id, side)
		"yinzhe2":
			_skill_hermit4(perk_id, side)
		"zhengyi2":
			_skill_justice2_4(side)
		"siwang2":
			_skill_death2_4(side)
		"lianren2":
			_skill_lianren2_4(side)
		"moshushi", "moshushi2", "huangdi", "huangdi2", "siwang", "yinzhe":
			_start_targeting4(perk_id, side)
		"diaodiao":
			# 正位:切换操控模式(己方↔非己方),跳过本回合
			control_foreign4[side] = not control_foreign4[side]
			_apply_skill_cd4(perk_id, side)
			_show_status4("倒吊人:切换为操控%s棋子" % ("非己方" if control_foreign4[side] else "己方"))
			_consume_turn_after_skill4()
		"diaodiao2":
			# 逆位:跳过本回合,下回合起获得其他所有方棋子控制权三回合
			controlled_all_turns4 = 3
			controlled_all_owner4 = side
			_apply_skill_cd4(perk_id, side)
			_show_status4("倒吊人:跳过本回合,下回合起控制其他方所有棋子三回合")
			_consume_turn_after_skill4()
		"xingxing2":
			# 星星逆位:获得 2 蓄势(每蓄势可免费移动一个兵),跳过本回合
			star2_charge4[side] += 2
			_apply_skill_cd4(perk_id, side)
			_show_status4("星星:获得 2 蓄势(可免费移动 2 个兵),跳过本回合")
			_consume_turn_after_skill4()
		_:
			_show_status4("[%s] 该主动技能暂未实现" %  perks_data[perk_id]["name"])
	# 联机主机:本地释放技能后广播屏幕中央提醒(其他端执行时由各入口补广播)
	# 目标型技能不在此广播:选完目标执行时才广播(见各 _handle_*_target4),避免提前/重复提醒
	if net_role == "host" and Global.from_lobby and not _is_targeting_skill(perk_id):
		notify_skill_used4.rpc(perk_id, side)


# 四人:记录技能使用(显示到对局记录)
# 对局记录用:简单方名(黑方/红方/绿方/蓝方,无上下左右)
func _side_short4(side: int) -> String:
	match side:
		1: return "黑方"
		0: return "红方"
		2: return "绿方"
		3: return "蓝方"
	return "方"


func _record_skill4(side: int, perk_id: String) -> void:
	var nm: String = perks_data[perk_id]["name"] if perks_data.has(perk_id) else perk_id
	_record4_history.append({"text": "%s 使用[%s]" % [_side_short4(side), nm], "turn": turn4, "side": side})
	_refresh_record4()


func _refresh_record4() -> void:
	if record_box == null:
		return
	for child in record_box.get_children():
		child.free()
	# 合并走子与技能,按玩家选择的颜色着色
	var idx := 0
	for m in _record4_history:
		var side: int = int(m.get("side", -1))
		var col: Color = Color(0.85, 0.82, 0.75)
		if side >= 0 and side <= 3:
			col = _side_color(side)
		var l := _make_label("%d. %s" % [idx + 1, m["text"]], 13, col)
		record_box.add_child(l)
		idx += 1


func _apply_skill_cd4(perk_id: String, side: int) -> void:
	var cd := _skill_cd_value(perk_id)
	if cd <= 0:
		return
	if perks4[side].has("liliang"):
		cd = maxi(cd - 2, 0)  # 力量:我方主动技能冷却-2
	# 注:逆位力量已改为"充能可累计至3倍上限",不再影响其他方冷却
	if cd > 0:
		skill_cd4[side][perk_id] = cd

# ==================== 四人目标选择(复制双人,去掉联机分支) ====================

func _start_targeting4(perk_id: String, side: int) -> void:
	targeting4 = {"perk": perk_id, "side": side, "stage": 1, "data": {}}
	selected4 = Vector2i(-1, -1)
	moves4 = []
	match perk_id:
		"moshushi", "moshushi2":
			_show_status4("选择要交换的第一个棋子")
		"huangdi", "huangdi2":
			_show_status4("选择己方一枚棋子")
		"zhanche", "zhanche2":
			_show_status4("选择己方的车")
		"siwang":
			_show_status4("选择己方一枚棋子(摧毁敌我同类型)")
		"diaodiao", "diaodiao2":
			_show_status4("选择要控制的对方棋子")
		"yinzhe":
			_show_status4("选择第一枚要隐身的己方棋子")
		_:
			_show_status4("选择目标:请点击棋盘上的棋子")
	queue_redraw()


func _handle_target_click4(pos: Vector2i) -> void:
	var perk_id: String = targeting4["perk"]
	var side: int = targeting4["side"]
	match perk_id:
		"moshushi", "moshushi2":
			_handle_swap_target4(pos, side, perk_id)
		"huangdi":
			_handle_king_guard4(pos, side)
		"huangdi2":
			_handle_king_counter4(pos, side)
		"zhanche", "zhanche2":
			_handle_chariot_target4(pos, side, perk_id)
		"siwang":
			_handle_death_target4(pos, side)
		"diaodiao", "diaodiao2":
			_handle_puppet_target4(pos, side, perk_id)
		"yinzhe":
			_handle_hermit_target4(pos, side)
		_:
			_done_targeting4()
	queue_redraw()


func _other_alive4(side: int) -> Array:
	var others: Array = []
	for s in 4:
		if s != side and alive4[s]:
			others.append(s)
	return others


func _handle_swap_target4(pos: Vector2i, side: int, perk_id: String) -> void:
	var need_side: int = side if perk_id == "moshushi" else -1
	if need_side < 0:
		# 进阶:可交换任意其他方棋子(选第一个)
		var p0 = board[pos.y][pos.x]
		if p0 == null or p0["side"] == side:
			_show_status4("请选择其他方的棋子")
			return
		# 逆位:其他方的将/帅不可被交换
		if p0["type"] == R.Type.KING:
			_show_status4("逆位魔术师:不能交换对方将/帅")
			return
		need_side = p0["side"]
	var p = board[pos.y][pos.x]
	if p == null or p["side"] != need_side:
		_show_status4("请选择%s的棋子" %  ("己方" if need_side == side else "对方"))
		return
	# 逆位:第二个目标也不能是其他方的将/帅
	if perk_id == "moshushi2" and p["type"] == R.Type.KING:
		_show_status4("逆位魔术师:不能交换对方将/帅")
		return
	if targeting4["stage"] == 1:
		targeting4["data"]["a"] = pos
		targeting4["stage"] = 2
		_show_status4("再选择要交换的第二个棋子")
		return
	var a: Vector2i = targeting4["data"]["a"]
	if pos == a:
		_show_status4("不能与自身交换")
		return
	if net_role != "local" and Global.from_lobby and net_role == "client":
		targeting4["data"]["b"] = pos
		_done_targeting4()
		return
	var pa = board[a.y][a.x]
	board[a.y][a.x] = p
	board[pos.y][pos.x] = pa
	_done_targeting4()
	_apply_skill_cd4(perk_id, side)
	_show_status4("魔术师:两子位置已交换")
	_show_skill_announce(perk_id, side)
	queue_redraw()
	_consume_turn_after_skill4()


func _handle_king_guard4(pos: Vector2i, side: int) -> void:
	var p = board[pos.y][pos.x]
	if p == null or p["side"] != side:
		_show_status4("请选择己方棋子")
		return
	if net_role != "local" and Global.from_lobby and net_role == "client":
		targeting4["data"]["target"] = pos
		_done_targeting4()
		return
	invincible_piece4 = pos
	invincible_piece_side4 = side
	invincible_piece_turns4 = 3
	_apply_skill_cd4("huangdi", side)
	_done_targeting4()
	_show_status4("皇帝:该子无敌(持续3回合)")
	_show_skill_announce("huangdi", side)
	queue_redraw()
	_consume_turn_after_skill4()


func _handle_king_counter4(pos: Vector2i, side: int) -> void:
	var p = board[pos.y][pos.x]
	if p == null or p["side"] != side:
		_show_status4("请选择己方棋子")
		return
	if net_role != "local" and Global.from_lobby and net_role == "client":
		targeting4["data"]["target"] = pos
		_done_targeting4()
		return
	suicide_mark4 = {"pos": pos, "side": side}
	_apply_skill_cd4("huangdi2", side)
	_done_targeting4()
	_show_status4("皇帝:标记棋子,被吃时同归于尽")
	_show_skill_announce("huangdi2", side)
	queue_redraw()
	_consume_turn_after_skill4()


# 隐者(普通):指定两子隐身两回合(四人版,分两步选己方两子)
func _handle_hermit_target4(pos: Vector2i, side: int) -> void:
	var p = board[pos.y][pos.x]
	if p == null or p["side"] != side:
		_show_status4("请选择己方棋子")
		return
	if targeting4["stage"] == 1:
		targeting4["data"]["a"] = pos
		targeting4["stage"] = 2
		_show_status4("再选择第二枚要隐身的己方棋子")
		return
	var a: Vector2i = targeting4["data"]["a"]
	if pos == a:
		_show_status4("不能与自身相同")
		return
	if net_role != "local" and Global.from_lobby and net_role == "client":
		targeting4["data"]["b"] = pos
		_done_targeting4()
		return
	_apply_hermit_target4(a, pos, side)
	_done_targeting4()
	_apply_skill_cd4("yinzhe", side)
	_show_status4("隐者:指定两子隐身两回合")
	_show_skill_announce("yinzhe", side)
	queue_redraw()
	_consume_turn_after_skill4()


# 隐者(普通):两子标记为隐身 2 回合(四人版,side+200 = 指定两子隐身)
func _apply_hermit_target4(a: Vector2i, b: Vector2i, side: int) -> void:
	hidden_pieces4[a] = side + 200
	hidden_turns4[a] = 2
	hidden_pieces4[b] = side + 200
	hidden_turns4[b] = 2


func _handle_death_target4(pos: Vector2i, side: int) -> void:
	var p = board[pos.y][pos.x]
	if p == null or p["side"] != side:
		_show_status4("请选择己方棋子")
		return
	if siwang_charge4[side] <= 0:
		_show_status4("[死亡] 充能中:己方每被吃 1 子充能 1 点")
		return
	if net_role != "local" and Global.from_lobby and net_role == "client":
		targeting4["data"]["target"] = pos
		_done_targeting4()
		return
	siwang_charge4[side] -= 1
	_destroy_same_type4(pos, side)
	_done_targeting4()
	_show_skill_announce("siwang", side)
	_consume_turn_after_skill4()


func _destroy_same_type4(pos: Vector2i, side: int) -> void:
	var p = board[pos.y][pos.x]
	var t: int = p["type"]
	var others := _other_alive4(side)
	others.shuffle()
	board[pos.y][pos.x] = null
	for os in others:
		var ep := Vector2i(-1, -1)
		for r in board.size():
			for c in board[r].size():
				var q = board[r][c]
				if q != null and q["side"] == os and q["type"] == t:
					ep = Vector2i(c, r)
					break
			if ep.x >= 0:
				break
		if ep.x >= 0:
			board[ep.y][ep.x] = null
			break
	_show_status4("死亡:敌我各一枚同类型子被摧毁")
	queue_redraw()


func _handle_puppet_target4(pos: Vector2i, side: int, perk_id: String) -> void:
	var p = board[pos.y][pos.x]
	if p == null or p["side"] == side:
		_show_status4("请选择对方的棋子")
		return
	if net_role != "local" and Global.from_lobby and net_role == "client":
		targeting4["data"]["target"] = pos
		_done_targeting4()
		return
	controlled_piece4 = {"pos": pos, "owner": side}
	controlled_turns4 = 3 if perk_id == "diaodiao2" else 1
	_apply_skill_cd4(perk_id, side)
	_done_targeting4()
	if perk_id == "diaodiao2":
		_show_status4("倒吊人:获得对方棋子控制权三回合(不能吃子)")
	else:
		_show_status4("倒吊人:已获得对方棋子控制权")
	_show_skill_announce(perk_id, side)
	queue_redraw()
	_consume_turn_after_skill4()


func _handle_chariot_target4(pos: Vector2i, side: int, perk_id: String) -> void:
	var stage: int = targeting4["stage"]
	var p = board[pos.y][pos.x]
	if stage == 1:
		if p == null or p["side"] != side or p["type"] != R.Type.ROOK:
			_show_status4("请选择己方的车")
			return
		targeting4["stage"] = 2
		targeting4["data"]["rook"] = pos
		_show_status4("再选择车相邻的一枚棋子(正位:己方;逆位:含敌方)")
	elif stage == 2:
		var rook: Vector2i = targeting4["data"]["rook"]
		var adj: bool = absi(pos.x - rook.x) + absi(pos.y - rook.y) == 1
		if perk_id == "zhanche2" and adj:
			adj = absi(pos.x - rook.x) != 1 or absi(pos.y - rook.y) != 1
		if p == null or not adj:
			_show_status4("请选择与车相邻(不含对角)的棋子" if perk_id == "zhanche2" else "请选择与车相邻的棋子")
			return
		if perk_id == "zhanche" and p["side"] != side:
			_show_status4("请选择与车相邻的己方棋子")
			return
		targeting4["stage"] = 3
		targeting4["data"]["piece"] = pos
		var perks_arr: Array = [perks4[0], perks4[1], perks4[2], perks4[3]]
		# 逆位:车移动到相邻子可落位;正位:相邻子移动到车可落位
		if perk_id == "zhanche2":
			targeting4["data"]["landings"] = R.raw_moves4(board, pos, perks_arr)
			_show_status4("点击可落位,将车移至此处(通过相邻子移动车)")
		else:
			targeting4["data"]["landings"] = R.raw_moves4(board, rook, perks_arr)
			_show_status4("点击车的可落位,将该子移至此处")
	elif stage == 3:
		var landings: Array = targeting4["data"]["landings"]
		if not pos in landings:
			_show_status4("请点击车的可落位点")
			return
		var from: Vector2i = targeting4["data"]["piece"]
		var rook_pos: Vector2i = targeting4["data"]["rook"]
		if perk_id == "zhanche2":
			# 逆位:移动车到相邻子的可落位
			var rook_piece = board[rook_pos.y][rook_pos.x]
			board[rook_pos.y][rook_pos.x] = null
			board[pos.y][pos.x] = rook_piece
			_show_status4("战车:车已移至相邻子的可落位")
		else:
			var piece = board[from.y][from.x]
			board[from.y][from.x] = null
			board[pos.y][pos.x] = piece
			_show_status4("战车:棋子已移至车可落位")
		_done_targeting4()
		_apply_skill_cd4(perk_id, side)
		_show_skill_announce(perk_id, side)
		queue_redraw()
		_consume_turn_after_skill4()


func _done_targeting4() -> void:
	var was_net: bool = targeting4.get("net", false)
	var perk: String = targeting4.get("perk", "")
	var side: int = targeting4.get("side", -1)
	var data: Dictionary = targeting4.get("data", {})
	targeting4 = {}
	selected4 = Vector2i(-1, -1)
	moves4 = []
	if was_net and net_role == "client":
		# 上报主机:目标型技能参数
		var params := {}
		if perk == "moshushi" or perk == "moshushi2":
			params = {"a": [data["a"].x, data["a"].y], "b": [data.get("b", data["a"]).x, data.get("b", data["a"]).y]}
		elif perk == "huangdi" or perk == "huangdi2":
			params = {"pos": [data.get("target", Vector2i(-1, -1)).x, data.get("target", Vector2i(-1, -1)).y]}
		elif perk == "siwang":
			params = {"pos": [data.get("target", Vector2i(-1, -1)).x, data.get("target", Vector2i(-1, -1)).y]}
		elif perk == "diaodiao" or perk == "diaodiao2":
			params = {"pos": [data.get("target", Vector2i(-1, -1)).x, data.get("target", Vector2i(-1, -1)).y]}
		elif perk == "yinzhe":
			params = {"a": [data.get("a", Vector2i(-1, -1)).x, data.get("a", Vector2i(-1, -1)).y], "b": [data.get("b", Vector2i(-1, -1)).x, data.get("b", Vector2i(-1, -1)).y]}
		request_skill4.rpc_id(1, perk, params)
		_show_status4("技能已发送,等待同步")


func _consume_turn_after_skill4() -> void:
	actions_left4 -= 1
	if actions_left4 <= 0:
		_end_turn4()
	else:
		_update_status4()
	queue_redraw()
	# 联机:技能可能消耗回合,结束后必须广播,否则其他端仍停留在等待(目标型技能在点击目标后才执行)
	if net_role == "host" and Global.from_lobby:
		_broadcast_state4()


func _net_avatar4(data: Dictionary, size: int) -> Texture2D:
	# 与双人 _enemy_icon_texture 一致:自定义头像 PNG 优先,否则颜色块
	if data.is_empty():
		return null
	var png = data.get("avatar_png")
	if png is PackedByteArray and (png as PackedByteArray).size() > 0:
		var img := Image.new()
		var err := img.load_png_from_buffer(png)
		if err == OK:
			img.resize(size, size, Image.INTERPOLATE_LANCZOS)
			return ImageTexture.create_from_image(img)
	if data.has("color"):
		# 无头像:返回颜色块纹理(color 是 [r,g,b] 数组)
		return Profile.color_icon(Profile.profile_color(data), size)
	return null


func _make_scroll_list(panel: FloatingPanel) -> VBoxContainer:
	# 在悬浮框内容区创建可滚动的技能卡列表
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(210, 250)
	panel.content.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	return box


# 头像框:Panel + 圆角,边框颜色由该方棋子颜色决定
func _make_badge_frame(pos: Vector2) -> Panel:
	var frame := Panel.new()
	frame.position = pos
	frame.size = Vector2(54, 54)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.22, 0.22, 0.27)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(3)
	frame.add_theme_stylebox_override("panel", sb)
	return frame


# 设置头像框描边颜色);active=true 时边框加粗发光(脉动由外部传 pulse)
func _set_frame_glow(frame: Panel, color: Color, active: bool, pulse: float) -> void:
	if frame == null:
		return
	var sb: StyleBoxFlat = frame.get_theme_stylebox("panel")
	if sb == null:
		return
	if active:
		sb.border_color = Color(color.r, color.g, color.b, pulse)
		sb.set_border_width_all(5)
		frame.self_modulate = Color(1, 1, 1, 0.7 + 0.3 * pulse)
	else:
		sb.border_color = Color(color.r, color.g, color.b, 1.0)
		sb.set_border_width_all(3)
		frame.self_modulate = Color(1, 1, 1, 1)


func _update_badge_glow() -> void:
	if status_label == null or ui == null:
		return
	var pulse := 0.55 + 0.45 * sin(_glow_time * 5.0)
	if four_mode:
		_update_badge_glow4(pulse)
		return
	# 双人:当前回合方头像框发光
	var self_side := _self_side()
	if turn == self_side:
		_set_frame_glow(my_badge_frame, _side_color(self_side), true, pulse)
		_set_frame_glow(enemy_badge_frame, _side_color(1 - self_side), false, pulse)
	else:
		_set_frame_glow(my_badge_frame, _side_color(self_side), false, pulse)
		_set_frame_glow(enemy_badge_frame, _side_color(1 - self_side), true, pulse)


# 四人模式:四方玩家头像栏(顶部),轮到走子方发光
func _update_badge_glow4(pulse: float) -> void:
	if _four_frames.is_empty():
		return
	var cur := current_side4()
	for entry in _four_frames:
		var frame: Panel = entry["frame"]
		var side: int = entry["side"]
		var color := _side_color(side)
		_set_frame_glow(frame, color, side == cur, pulse)


func _build_player_badges() -> void:
	# 右上:敌方头像 + 用户名(头像框描边=敌方棋子颜色,轮到走子时发光)
	enemy_badge_frame = _make_badge_frame(Vector2(1220 - 54, 4))
	ui.add_child(enemy_badge_frame)
	enemy_badge_icon = TextureRect.new()
	enemy_badge_icon.position = Vector2(3, 3)
	enemy_badge_icon.size = Vector2(48, 48)
	enemy_badge_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	enemy_badge_frame.add_child(enemy_badge_icon)
	enemy_badge_name = _make_label("", 14, Color(0.9, 0.7, 0.6))
	enemy_badge_name.position = Vector2(1060, 58)
	enemy_badge_name.size = Vector2(208, 22)
	enemy_badge_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.add_child(enemy_badge_name)

	# 左下:我方头像 + 用户名(头像框描边=我方棋子颜色,轮到走子时发光)
	my_badge_frame = _make_badge_frame(Vector2(12, 720 - 68))
	ui.add_child(my_badge_frame)
	my_badge_icon = TextureRect.new()
	my_badge_icon.position = Vector2(3, 3)
	my_badge_icon.size = Vector2(48, 48)
	my_badge_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	my_badge_frame.add_child(my_badge_icon)
	my_badge_name = _make_label("", 14, Color(0.8, 0.9, 0.75))
	my_badge_name.position = Vector2(72, 720 - 60)
	my_badge_name.size = Vector2(220, 22)
	ui.add_child(my_badge_name)

	_update_player_badges()


func _update_player_badges() -> void:
	# 我方(本地用户资料)
	my_info = Profile.load_profile()
	if my_badge_icon != null:
		my_badge_icon.texture = Profile.avatar_icon(my_info, 48)
		my_badge_name.text = Profile.username(my_info)
	# 敌方:联机时由对手资料传输;本地用默认
	if enemy_info.is_empty():
		if Global.game_mode == "ai":
			enemy_info = {"username": "电脑", "color": [0.5, 0.5, 0.55]}
		else:
			enemy_info = {"username": "黑方玩家", "color": [0.5, 0.5, 0.55]}
	if enemy_badge_icon != null:
		enemy_badge_icon.texture = _enemy_icon_texture(48)
		enemy_badge_name.text = Profile.username(enemy_info)


func _enemy_icon_texture(size: int) -> Texture2D:
	var png = enemy_info.get("avatar_png")
	if png is PackedByteArray and (png as PackedByteArray).size() > 0:
		var img := Image.new()
		if img.load_png_from_buffer(png) == OK:
			img.resize(size, size, Image.INTERPOLATE_LANCZOS)
			return ImageTexture.create_from_image(img)
	return Profile.color_icon(Profile.profile_color(enemy_info), size)


func _make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _make_button(text: String, pos: Vector2, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.add_theme_font_override("font", _font())
	b.add_theme_font_size_override("font_size", 20)
	Global.style_flat_button(b)
	return b


var _font_cache: Font


func _set_demo_hint() -> void:
	if Global.demo_perk != "" and status_label != null:
		status_label.text = "图鉴演示:你拥有[%s],机器人无技能" % perks_data[Global.demo_perk]["name"]


func _font() -> Font:
	if _font_cache == null:
		_font_cache = load("res://fonts/zpix.ttf")

	return _font_cache


# ==================== 网络(局域网联机) ====================

# 大厅已建立连接:主机直接开局,客户端等待主机广播
# ==================== 联机四人:各选各的技能 ====================

func _find_my_side4() -> int:
	# 从大厅玩家表找到自己(pid==multiplayer.get_unique_id())对应的 side
	var my_pid := multiplayer.get_unique_id()
	for side in Global.lobby_players:
		var p: Dictionary = Global.lobby_players[side]
		if int(p.get("pid", -1)) == my_pid:
			return int(side)
	return -1


func _build_four_side_map() -> void:
	four_side_to_peer = {}
	for side in Global.lobby_players:
		var p: Dictionary = Global.lobby_players[side]
		four_side_to_peer[int(side)] = int(p.get("pid", -1))


func _from_lobby_start4() -> void:
	if net_role == "host":
		# 等所有客户端进入 game 场景后发 client_ready 再开局
		_lobby_ready_done = false
		four_ready_count = 0
		# 单人开房(全部机器人补位,无真实客户端):无需等待,直接开始技能抽取
		if _real_client_count4() <= 0:
			_begin_four_draft_host()
			return
		net_wait_label = _make_label("等待玩家进入对局...", 26, Color(0.95, 0.85, 0.6))
		net_wait_label.position = Vector2(0, 200)
		net_wait_label.size = Vector2(1280, 120)
		net_wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ui.add_child(net_wait_label)
	else:
		# 客户端:显示等待,通知主机已就绪
		phase = Phase.DRAFT
		net_wait_label = _make_label("等待主机开始对局...", 26, Color(0.95, 0.85, 0.6))
		net_wait_label.position = Vector2(0, 200)
		net_wait_label.size = Vector2(1280, 120)
		net_wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ui.add_child(net_wait_label)
		client_ready4.rpc_id(1)
		send_profile.rpc_id(1, Profile.to_net_data())


# 客户端 → 主机:已进入对局场景(四人模式:所有客户端齐了才开局)
@rpc("any_peer", "reliable")
func client_ready4() -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	# 对局已开始:客户端重连,重发完整状态并关联席位
	if _four_draft_started and phase == Phase.PLAY:
		_four_ready_done[pid] = true
		# 把重连 pid 关联到空缺席位(若无空缺则匹配原 pid)
		var assigned := false
		var assign_side := -1
		for side in _four_side_absent:
			if _four_side_absent[side]:
				four_side_to_peer[side] = pid
				_four_side_absent[side] = false
				assigned = true
				assign_side = side
				print("NET4: client RECONNECT pid=", pid, " -> side ", side)
				break
		if not assigned:
			for side in four_side_to_peer:
				if int(Global.lobby_players.get(side, {}).get("pid", -1)) == pid:
					assign_side = side
					print("NET4: client RECONNECT same pid=", pid, " side=", side)
					break
		# 重连客户端进程重启后没有 lobby_players,必须告知其 side
		var data := _state_to_data4()
		data["my_side4"] = assign_side
		sync_state4.rpc_id(pid, data)
		return
	if _four_ready_done.has(pid):
		return
	_four_ready_done[pid] = true
	four_ready_count += 1
	print("NET4: client ready pid=", pid, " count=", four_ready_count, "/", _real_client_count4())
	# 所有真实客户端都 ready 才开局(机器人无需 ready)
	if four_ready_count >= _real_client_count4():
		_begin_four_draft_host()


func three_peers4() -> int:
	return 3


# 真实客户端数量(lobby_players 中 pid>0 且非 AI 的,不含 host)
# 注意:host 单人开房(全部机器人补位)时为 0,此时 host 无需等待,直接开局
func _real_client_count4() -> int:
	var n := 0
	for side in Global.lobby_players:
		var info: Dictionary = Global.lobby_players[side]
		var pid := int(info.get("pid", -1))
		if pid > 1 and not bool(info.get("is_ai", false)):
			n += 1
	return n


# 主机:开始四人 DRAFT(自己选 + 给每个客户端发其方的选项)
func _begin_four_draft_host() -> void:
	_four_draft_started = true
	if net_wait_label != null:
		net_wait_label.queue_free()
		net_wait_label = null
	phase = Phase.SKILL_DRAFT
	var my_side: int = my_side4 if my_side4 >= 0 else 1
	four_draft_picks = {0: [], 1: [], 2: [], 3: []}
	# 44→32→4 组(正逆位不同组),每组 8 个;host 用自己组,客户端各发一组
	var groups: Array = Perks.build_four_pools(Global.perk_pool)
	var my_group: Array = groups[0]
	var used := {0: true}  # 标记组 0 已给 host,其余分给客户端
	var side_to_group := {my_side: 0}
	var gi := 1
	for side in four_side_to_peer:
		if side == my_side:
			continue
		var peer: int = four_side_to_peer[side]
		if peer <= 0:
			continue  # 机器人补位方无客户端,不发送
		side_to_group[side] = gi
		var opts: Array = groups[gi]
		send_four_draft_options.rpc_id(peer, side, opts, Global.perk_pool)
		gi += 1
	# 机器人补位方:自动随机选 3 个技能
	for side in Global.lobby_players:
		var si: int = int(side)
		var info: Dictionary = Global.lobby_players[side]
		# 跳过 host 自己和真实客户端;仅 AI 补位方自动选
		if si == my_side or not bool(info.get("is_ai", false)):
			continue
		var ai_group: Array = groups[gi] if gi < groups.size() else []
		gi += 1
		if ai_group.is_empty():
			continue
		ai_group.shuffle()
		four_draft_picks[si] = [ai_group[0], ai_group[1], ai_group[2]]
		perks4[si] = {}
		for id in four_draft_picks[si]:
			perks4[si][id] = true
	# host 自己选
	draft4_side = my_side
	draft4_round = 0
	draft4_options = my_group
	_draft_selected4 = []
	_update_draft_ui()
	if _has_user_arg("--auto"):
		call_deferred("_auto_pick_four_client")


# 主机 → 客户端:该客户端所属方的三选一选项
@rpc("authority", "reliable")
func send_four_draft_options(side: int, options: Array, pool: String) -> void:
	if Global.standard_mode:
		return
	Global.perk_pool = pool
	perks_data = Perks.load_perks(pool)
	my_side4 = side
	own_side = side
	print("NET4: client got options side=", side, " opts=", options)
	phase = Phase.SKILL_DRAFT
	draft4_side = side
	draft4_round = 0
	draft4_options = []
	for o in options:
		draft4_options.append(o)
	_update_draft_ui()
	if _has_user_arg("--auto"):
		call_deferred("_auto_pick_four_client")


# 客户端 → 主机:该方选完技能上报
@rpc("any_peer", "reliable")
func send_four_draft_picks(side: int, picks: Array) -> void:
	if not multiplayer.is_server():
		return
	if Global.standard_mode:
		return
	four_draft_picks[side] = picks
	print("NET4: host got picks side=", side, " picks=", picks)
	_check_four_draft_done()


# 主机:检查四方是否都选完
func _check_four_draft_done() -> void:
	var my_side: int = my_side4 if my_side4 >= 0 else 1
	# 检查所有有玩家的 side(含机器人)都选完
	var all_sides: Array = []
	for side in four_side_to_peer:
		all_sides.append(side)
	for side in Global.lobby_players:
		if not int(side) in all_sides:
			all_sides.append(int(side))
	for side in all_sides:
		if four_draft_picks[side].is_empty() and side != my_side:
			return
	if four_draft_picks[my_side].is_empty():
		return
	# 组装 perks4 并广播开局
	var all_picks := {}
	for side in all_sides:
		all_picks[str(side)] = four_draft_picks[side]
	start_four_game.rpc(all_picks, Global.perk_pool)


# 主机 → 所有人:开局广播(每方技能)
@rpc("authority", "call_local", "reliable")
func start_four_game(picks: Dictionary, pool: String) -> void:
	Global.perk_pool = pool
	perks_data = Perks.load_perks(pool)
	perks4 = {0: {}, 1: {}, 2: {}, 3: {}}
	for side_str in picks:
		var side: int = int(side_str)
		for id in picks[side_str]:
			perks4[side][id] = true
	if draft_root != null:
		draft_root.queue_free()
		draft_root = null
	if net_wait_label != null:
		net_wait_label.queue_free()
		net_wait_label = null
	_apply_four_skills_setup()
	_start_four_game()


func _show_net_draft_wait4(text: String) -> void:
	if draft_root != null:
		draft_root.queue_free()
		draft_root = null
	draft_root = Control.new()
	draft_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(draft_root)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.1, 0.09, 0.98)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	draft_root.add_child(bg)
	var label := _make_label(text, 26, Color(0.95, 0.85, 0.6))
	label.position = Vector2(0, 220)
	label.size = Vector2(1280, 160)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	draft_root.add_child(label)
	Global.pop_in_layer(draft_root, 0.4)


func _apply_four_skills_setup() -> void:
	# 塔(普通):开局兵线补充兵
	for side in 4:
		if perks4[side].has("ta"):
			_add_reinforcement4(side, 4)
	# 塔(进阶):开局失去所有兵
	for side in 4:
		if perks4[side].has("ta2"):
			_remove_all_pawns4(side)


# 联机客户端:自动选自己方的技能
func _auto_pick_four_client() -> void:
	if phase != Phase.SKILL_DRAFT or draft4_options.is_empty():
		return
	_draft_selected4 = []
	for i in mini(3, draft4_options.size()):
		_draft_selected4.append(draft4_options[i])
	_confirm_draft4()


func _from_lobby_start() -> void:
	if net_role == "host":
		# 等客户端进入 game 场景后发 client_ready 再开局:
		# 过早广播 RPC 会在客户端场景未就绪时丢失,导致对方永远等待
		_lobby_ready_done = false
		net_wait_label = _make_label("等待对方进入对局...", 26, Color(0.95, 0.85, 0.6))
		net_wait_label.position = Vector2(0, 200)
		net_wait_label.size = Vector2(1280, 120)
		net_wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ui.add_child(net_wait_label)
	else:
		# 客户端:显示等待,通知主机已就绪
		phase = Phase.DRAFT
		net_wait_label = _make_label("等待主机开始对局...", 26, Color(0.95, 0.85, 0.6))
		net_wait_label.position = Vector2(0, 200)
		net_wait_label.size = Vector2(1280, 120)
		net_wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ui.add_child(net_wait_label)
		client_ready.rpc_id(1)
		# 复用连接时 connected_to_server 不会再次触发,补发资料
		send_profile.rpc_id(1, Profile.to_net_data())


# 客户端 → 主机:已进入对局场景,可以开局了(防 RPC 丢失的握手)
@rpc("any_peer", "reliable")
func client_ready() -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	if pid <= 0 or _lobby_ready_done:
		return
	_lobby_ready_done = true
	if net_wait_label != null:
		net_wait_label.queue_free()
		net_wait_label = null
	print("NET: client ready, starting game for peer=", pid)
	_on_peer_connected(pid)


# ==================== 聊天指令系统 ====================
# 通过聊天框输入指令(联机对局内可用,host 权威执行):
#   /place x y 类型   放置棋子(类型:帅将仕士相象马车炮兵卒后 或 k/a/e/h/r/c/p)
#   /place x y null   摧毁该位置棋子
#   /skill 方 id on|off   添加/移除技能(id 见技能池;方:红/黑/绿/蓝 或 0-3)
#   /charge 方 id 值  设置技能充能(皇后/死亡充能、星星蓄势等)
#   /state 方 无敌|反制  该方所有棋子无敌/反制
#   /state x y 隐身|显形  指定位置棋子隐身/显形
# ==================== 聊天指令 Tab 补全 ====================
# 返回 {text: 补全后的输入, hint: 候选提示字符串/数组}
func _chat_tab_complete(text: String) -> Dictionary:
	var t := text
	var trimmed := t.strip_edges()
	# 空输入或仅 "/":提示命令列表(字符串,不循环)
	if trimmed.is_empty() or trimmed == "/":
		return {"text": t, "hint": "/place x y 类型|null\n/skill 方 id on|off\n/charge 方 id 值\n/state 方 无敌|反制 | /state x y 隐身|显形"}
	var parts := trimmed.split(" ", false)
	if parts.is_empty():
		return {"text": t, "hint": ""}
	var cmd := String(parts[0]).to_lower()
	# 命令名补全(输入 /pl 等前缀 → 补全命令)
	if not parts[0].begins_with("/") or parts[0] == "/" or (parts.size() == 1 and not trimmed.ends_with(" ")):
		var cmds := ["/place ", "/skill ", "/charge ", "/state "]
		var matched: Array = []
		for c in cmds:
			if c.begins_with(parts[0]):
				matched.append(c)
		if matched.size() == 1:
			return {"text": matched[0], "hint": ""}
		if matched.size() > 1:
			return {"text": t, "hint": matched}
		return {"text": t, "hint": cmds}
	# 参数补全
	match cmd:
		"/place":
			# /place x y 类型|null(始终尝试补全最后一个参数)
			if parts.size() >= 2 and parts.size() <= 4:
				var piece_names := ["帅", "将", "仕", "士", "相", "象", "马", "车", "炮", "兵", "卒", "后", "null"]
				var cur := parts[3] if parts.size() >= 4 else ""
				var matched_pieces: Array = []
				for p in piece_names:
					if p.begins_with(cur):
						matched_pieces.append("/place %s %s %s" % [parts[1], parts[2], p])
				if matched_pieces.size() == 1:
					return {"text": String(matched_pieces[0]), "hint": ""}
				return {"text": t, "hint": matched_pieces if not matched_pieces.is_empty() else piece_names}
			return {"text": t, "hint": ""}
		"/skill":
			if parts.size() <= 2:
				var cur_side := parts[1] if parts.size() >= 2 else ""
				var sides := ["红", "黑", "绿", "蓝"]
				var matched_sides: Array = []
				for s in sides:
					if s.begins_with(cur_side):
						matched_sides.append("/skill %s " % s)
				if matched_sides.size() == 1:
					return {"text": String(matched_sides[0]), "hint": ""}
				return {"text": t, "hint": matched_sides if not matched_sides.is_empty() else sides}
			if parts.size() <= 3:
				var cur_id := parts[2] if parts.size() >= 3 else ""
				var ids: Array = []
				if not perks_data.is_empty():
					for id in perks_data:
						ids.append(String(id))
				var matched_ids: Array = []
				for id in ids:
					if id.begins_with(cur_id):
						matched_ids.append("/skill %s %s " % [parts[1], id])
				if matched_ids.size() == 1:
					return {"text": String(matched_ids[0]), "hint": ""}
				return {"text": t, "hint": matched_ids if not matched_ids.is_empty() else ids}
			# on/off
			var cur_sw := parts[3] if parts.size() >= 4 else ""
			var sw := ["on", "off"]
			var matched_sw: Array = []
			for s2 in sw:
				if s2.begins_with(cur_sw):
					matched_sw.append("/skill %s %s %s" % [parts[1], parts[2], s2])
			if matched_sw.size() == 1:
				return {"text": String(matched_sw[0]), "hint": ""}
			return {"text": t, "hint": matched_sw if not matched_sw.is_empty() else sw}
		"/charge":
			if parts.size() <= 2:
				var cur_side2 := parts[1] if parts.size() >= 2 else ""
				var sides2 := ["红", "黑", "绿", "蓝"]
				var matched_sides2: Array = []
				for s in sides2:
					if s.begins_with(cur_side2):
						matched_sides2.append(s)
				if matched_sides2.size() == 1:
					return {"text": "/charge %s " % matched_sides2[0], "hint": ""}
				return {"text": t, "hint": matched_sides2 if not matched_sides2.is_empty() else sides2}
			if parts.size() <= 3:
				var cur_cid := parts[2] if parts.size() >= 3 else ""
				var cids := ["huanghou", "huanghou2", "siwang", "siwang2", "xingxing2"]
				var matched_cids: Array = []
				for c in cids:
					if c.begins_with(cur_cid):
						matched_cids.append("/charge %s %s " % [parts[1], c])
				if matched_cids.size() == 1:
					return {"text": String(matched_cids[0]), "hint": ""}
				return {"text": t, "hint": matched_cids if not matched_cids.is_empty() else cids}
			return {"text": t, "hint": "值(0-3)"}
		"/state":
			# 坐标形式 /state x y 状态:parts[1] 是数字
			var state_is_xy: bool = parts.size() >= 2 and parts[1].is_valid_int()
			if state_is_xy:
				# 补状态名(隐身/显形)
				var st_all2 := ["隐身", "显形"]
				var cur4 := parts[3] if parts.size() >= 4 else ""
				var matched_st3: Array = []
				for s5 in st_all2:
					if s5.begins_with(cur4):
						matched_st3.append("/state %s %s %s" % [parts[1], parts[2], s5])
				if matched_st3.size() == 1:
					return {"text": String(matched_st3[0]), "hint": ""}
				return {"text": t, "hint": matched_st3 if not matched_st3.is_empty() else st_all2}
			# 方形式:补方名
			if parts.size() <= 2:
				var cur2 := parts[1] if parts.size() >= 2 else ""
				var sides3 := ["红", "黑", "绿", "蓝"]
				var matched_sides3: Array = []
				for s in sides3:
					if s.begins_with(cur2):
						matched_sides3.append("/state %s " % s)
				if matched_sides3.size() == 1:
					return {"text": String(matched_sides3[0]), "hint": ""}
				return {"text": t, "hint": matched_sides3 if not matched_sides3.is_empty() else sides3}
			# 补状态名(无敌/反制)
			var cur3 := parts[2] if parts.size() >= 3 else ""
			var st_all := ["无敌", "反制"]
			var matched_st2: Array = []
			for s4 in st_all:
				if s4.begins_with(cur3):
					matched_st2.append("/state %s %s" % [parts[1], s4])
			if matched_st2.size() == 1:
				return {"text": String(matched_st2[0]), "hint": ""}
			return {"text": t, "hint": matched_st2 if not matched_st2.is_empty() else st_all}
	return {"text": t, "hint": ""}


func _try_exec_command(text: String) -> bool:
	var t := text.strip_edges()
	if not t.begins_with("/"):
		return false
	var parts := t.split(" ", false)
	if parts.is_empty():
		return true
	var cmd := String(parts[0]).to_lower()
	match cmd:
		"/place":
			if parts.size() < 3:
				_show_command_result("用法: /place x y 类型|null")
				return true
			var x := int(parts[1])
			var y := int(parts[2])
			if not R.in_board(Vector2i(x, y)):
				_show_command_result("坐标越界")
				return true
			if parts.size() >= 4 and parts[3].to_lower() == "null":
				board[y][x] = null
				_show_command_result("已摧毁 (%d,%d)" % [x, y])
			else:
				var ptype := _piece_type_from_name(parts[3])
				if ptype < 0:
					_show_command_result("未知棋子类型: %s" % parts[3])
					return true
				board[y][x] = R.make_piece(current_side4() if four_mode else turn, ptype)
				_show_command_result("已在 (%d,%d) 放置 %s" % [x, y, R.PIECE_NAMES.get(ptype, str(ptype))])
			queue_redraw()
			_broadcast_state() if net_role == "host" else null
			return true
		"/skill":
			if parts.size() < 4:
				_show_command_result("用法: /skill 方 id on|off")
				return true
			var side := _side_from_name(parts[1])
			if side < 0:
				_show_command_result("未知方: %s" % parts[1])
				return true
			var id := parts[2]
			var onoff := parts[3].to_lower()
			if four_mode:
				if onoff == "on" or onoff == "true" or onoff == "1":
					perks4[side][id] = true
				else:
					perks4[side].erase(id)
				_show_command_result("已%s %s 的技能 %s" % ["添加" if onoff == "on" or onoff == "true" or onoff == "1" else "移除", _side_name(side), id])
			else:
				if onoff == "on" or onoff == "true" or onoff == "1":
					perks_of(side)[id] = true
				else:
					perks_of(side).erase(id)
				_show_command_result("已%s %s 的技能 %s" % ["添加" if onoff == "on" or onoff == "true" or onoff == "1" else "移除", _side_name(side), id])
			_refresh_perk_panels() if not four_mode else _refresh_perk_panels4()
			queue_redraw()
			_broadcast_state() if net_role == "host" else null
			return true
		"/charge":
			if parts.size() < 4:
				_show_command_result("用法: /charge 方 id 值")
				return true
			var side := _side_from_name(parts[1])
			if side < 0:
				_show_command_result("未知方: %s" % parts[1])
				return true
			var id := parts[2]
			var val := int(parts[3])
			if four_mode:
				match id:
					"huanghou", "huanghou2":
						queen_charge4[side] = val
					"siwang", "siwang2":
						siwang_charge4[side] = val
					"xingxing2":
						star2_charge4[side] = val
					_:
						_show_command_result("未知充能技能: %s" % id)
						return true
			else:
				match id:
					"huanghou", "huanghou2":
						queen_charge[side] = val
					"siwang", "siwang2":
						siwang_charge[side] = val
					"xingxing2":
						star2_charge[side] = val
					_:
						_show_command_result("未知充能技能: %s" % id)
						return true
			_show_command_result("%s 的 %s 充能设为 %d" % [_side_name(side), id, val])
			_refresh_perk_panels() if not four_mode else _refresh_perk_panels4()
			queue_redraw()
			_broadcast_state() if net_role == "host" else null
			return true
		"/state":
			if parts.size() < 3:
				_show_command_result("用法: /state 方 无敌|反制  或  /state x y 隐身|显形")
				return true
			# 坐标形式 /state x y 隐身|显形:parts[1] 是数字且棋盘内
			var is_xy: bool = parts.size() >= 4 and parts[1].is_valid_int() and parts[2].is_valid_int() \
				and R.in_board(Vector2i(int(parts[1]), int(parts[2])))
			var s := -1 if is_xy else _side_from_name(parts[1])
			if s >= 0:
				var st := parts[2].to_lower()
				if st == "无敌" or st == "invincible":
					if four_mode:
						invincible_side4 = s
					else:
						invincible_side = s
					_show_command_result("%s 所有棋子无敌" % _side_name(s))
				elif st == "反制" or st == "counter":
					if four_mode:
						counter_side4 = s
					else:
						counter_side = s
					_show_command_result("%s 所有棋子反制" % _side_name(s))
				else:
					_show_command_result("未知状态: %s (可用: 无敌/反制)" % parts[2])
					return true
			else:
				# /state x y 隐身|显形
				if parts.size() < 4:
					_show_command_result("用法: /state 方 无敌|反制  或  /state x y 隐身|显形")
					return true
				var x := int(parts[1])
				var y := int(parts[2])
				var st := parts[3].to_lower()
				var ppos := Vector2i(x, y)
				if four_mode:
					if st == "隐身" or st == "hidden":
						hidden_pieces4[ppos] = current_side4() + 100
					else:
						hidden_pieces4.erase(ppos)
				else:
					if st == "隐身" or st == "hidden":
						hidden_pieces[ppos] = turn + 100
					else:
						hidden_pieces.erase(ppos)
				_show_command_result("(%d,%d) %s" % [x, y, "已隐身" if st == "隐身" or st == "hidden" else "已显形"])
			queue_redraw()
			_broadcast_state() if net_role == "host" else null
			return true
		_:
			_show_command_result("未知指令: %s" % cmd)
			return true
	return true


func _show_command_result(msg: String) -> void:
	if chat != null:
		chat.add_message("指令", msg)
	elif status_label != null:
		status_label.text = msg


# 方名 → side(双人:红/黑;四人:红/黑/绿/蓝;也支持 0-3 数字)
func _side_from_name(s: String) -> int:
	var n := s.to_lower()
	match n:
		"红", "red", "r", "0": return 0
		"黑", "black", "b", "1": return 1
		"绿", "green", "g", "2": return 2
		"蓝", "blue", "l", "3": return 3
	return -1


func _side_name(side: int) -> String:
	if four_mode:
		return SIDE_NAMES4.get(side, "方")
	return "红方" if side == R.Side.RED else "黑方"


# 棋子类型名 → Type(支持中文名与单字母)
func _piece_type_from_name(s: String) -> int:
	var n := s.to_lower()
	match n:
		"帅", "将", "王", "k": return R.Type.KING
		"仕", "士", "a": return R.Type.ADVISOR
		"相", "象", "e": return R.Type.ELEPHANT
		"马", "h": return R.Type.HORSE
		"车", "車", "r": return R.Type.ROOK
		"炮", "砲", "c": return R.Type.CANNON
		"兵", "卒", "p": return R.Type.PAWN
		"后", "q": return R.Type.QUEEN
	return -1


# 对局聊天:host 权威转发(客户端发到主机,host 显示并广播给所有人)
func _send_chat_game(text: String) -> void:
	# 指令:host 本地执行;client 上报 host 执行
	if text.strip_edges().begins_with("/"):
		if net_role == "host":
			_try_exec_command(text)
		else:
			send_chat_game.rpc_id(1, text)
		return
	if net_role == "host":
		var who := _chat_name_host()
		if chat != null:
			chat.add_message(who, text)
		send_chat_game_relay.rpc(who, text)
	else:
		send_chat_game.rpc_id(1, text)


func _chat_name_host() -> String:
	if Global.lobby_players != {}:
		for side in Global.lobby_players:
			if int(Global.lobby_players[side].get("pid", -1)) == 1:
				return Global.lobby_players[side].get("name", "我")
	return Profile.username(Profile.load_profile())


@rpc("any_peer", "reliable")
func send_chat_game(text: String) -> void:
	if net_role != "host":
		return
	# 客户端发来的指令:host 权威执行
	if text.strip_edges().begins_with("/"):
		_try_exec_command(text)
		return
	var who: String = "玩家"
	var pid := multiplayer.get_remote_sender_id()
	if Global.lobby_players != {}:
		for side in Global.lobby_players:
			if int(Global.lobby_players[side].get("pid", -1)) == pid:
				who = Global.lobby_players[side].get("name", "玩家")
				break
	if chat != null:
		chat.add_message(who, text)
	send_chat_game_relay.rpc(who, text)


@rpc("authority", "reliable")
func send_chat_game_relay(who: String, text: String) -> void:
	if chat != null:
		chat.add_message(who, text)


func _show_net_wait() -> void:
	phase = Phase.DRAFT
	draft_root = Control.new()
	draft_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(draft_root)

	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.1, 0.09, 0.98)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	draft_root.add_child(bg)

	var label := _make_label("", 26, Color(0.95, 0.85, 0.6))
	label.position = Vector2(0, 200)
	label.size = Vector2(1280, 120)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	draft_root.add_child(label)
	net_wait_label = label
	Global.pop_in_layer(draft_root, 0.4)

	var mode_text := "技能模式" if not Global.standard_mode else "标准模式"
	if net_role == "host":
		label.text = "等待对手连接...( %s )\n\n本机 IP: %s\n(对方在联机菜单输入此 IP 加入)" % [mode_text, _local_ip()]
		_setup_host()
	else:
		label.text = "连接中 %s ...( %s )" % [Global.server_ip, mode_text]
		_setup_client()


func _local_ip() -> String:
	for addr in IP.get_local_addresses():
		if addr.begins_with("127.") or addr.contains(":"):
			continue
		return addr
	return "未知"


func _setup_host() -> void:
	print("NET: creating server...")
	# 清理上次联机的 peer:回主菜单再建房时,旧 ENet host 未释放会占住端口
	multiplayer.multiplayer_peer = null
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(Global.port, 1)
	print("NET: create_server err=", err)
	if err != OK:
		status_label.text = "创建房间失败(端口被占用?)"
		return
	print("NET: assigning multiplayer_peer...")
	multiplayer.multiplayer_peer = peer
	print("NET: peer assigned, connecting signals")
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("NET: host ready on port ", Global.port)


# 断线重连:重新建立连接
func _try_reconnect() -> void:
	if multiplayer.multiplayer_peer != null:
		return
	print("NET: retrying connection to ", Global.server_ip, ":", Global.port)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(Global.server_ip, Global.port)
	if err != OK:
		status_label.text = "重连失败,将再次尝试..."
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_peer_disconnected)


func _setup_client() -> void:
	print("NET: creating client peer...")
	# 清理上次联机的 peer(回菜单再加入时旧连接不会残留)
	multiplayer.multiplayer_peer = null
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(Global.server_ip, Global.port)
	print("NET: create_client err=", err)
	if err != OK:
		status_label.text = "无法连接服务器"
		return
	print("NET: assigning client peer...")
	multiplayer.multiplayer_peer = peer
	print("NET: client peer assigned")
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_peer_disconnected)
	print("NET: client connecting to ", Global.server_ip)


func _on_connected_to_server() -> void:
	print("NET: client connected to server, waiting for perks")
	if _reconnecting:
		_reconnecting = false
		# 重连成功:重新握手(四人)或等待主机重发状态
		if four_mode:
			client_ready4.rpc_id(1)
			send_profile.rpc_id(1, Profile.to_net_data())
			status_label.text = "已重连,等待同步..."
		return
	# 把自己的用户资料发给主机
	send_profile.rpc_id(1, Profile.to_net_data())
	# 技能模式:等待主机(红方)先选完技能
	if not Global.standard_mode and net_wait_label != null:
		net_wait_label.text = "已连接,等待主机选择技能...\n\n(主机选完会把黑方的技能选项发给你)"


func _on_connection_failed() -> void:
	status_label.text = "连接失败,请检查 IP 与网络"
	if net_wait_label != null:
		net_wait_label.text = "连接失败\n请返回菜单检查 IP 后重试"


func _on_peer_connected(peer_id: int) -> void:
	client_peer_id = peer_id
	print("NET: client connected, peer=", peer_id)
	print("NET: host standard_mode=", Global.standard_mode)
	# 标准模式:双方无技能,直接开局
	if Global.standard_mode:
		perks_red = {}
		perks_black = {}
		assign_perks.rpc_id(peer_id, perks_black, perks_red, Profile.to_net_data())
		_start_net_game()
		return
	# 技能模式:双方同步三选一——主机为双方各抽 3 个互不重复的选项,同时开始选
	perks_red = {}
	perks_black = {}
	draft_red_done = false
	draft_black_done = false
	phase = Phase.SKILL_DRAFT
	draft_side = R.Side.RED
	draft_round = 0
	var taken := {}
	draft_options = Perks.draw_options(3, taken, Global.perk_pool)
	for o in draft_options:
		taken[o] = true
	var black_opts := Perks.draw_options(3, taken, Global.perk_pool)
	print("NET: host red options: ", draft_options, " black options: ", black_opts)
	send_black_draft_options.rpc_id(peer_id, black_opts, Global.perk_pool)
	_update_draft_ui()
	if _has_user_arg("--auto"):
		call_deferred("_auto_pick_host")


func _on_peer_disconnected(id: int) -> void:
	print("NET: peer disconnected pid=", id)
	# 四人联机客户端断线:自动重连
	if four_mode and net_role == "client" and phase == Phase.PLAY and winner4 < 0:
		_reconnecting = true
		_reconnect_timer = 0.0
		status_label.text = "连接断开,正在重连..."
		return
	# 四人主机:标记断线席位(保留,等待重连;不判负)
	if four_mode and net_role == "host" and phase == Phase.PLAY:
		for side in four_side_to_peer:
			if four_side_to_peer[side] == id:
				_four_side_absent[side] = true
				_show_status4("%s 掉线,等待重连..." % SIDE_NAMES4[side])
				return
	status_label.text = "对方已断开连接"
	if phase != Phase.OVER:
		phase = Phase.OVER


@rpc("authority", "reliable")
func assign_perks(black: Dictionary, red: Dictionary, host_profile: Dictionary) -> void:
	perks_black = black
	perks_red = red
	print("NET: client got perks, black=", perks_black.keys(), " red=", perks_red.keys())
	enemy_info = host_profile
	_update_player_badges()
	_start_net_game()


# 客户端 → 主机:发送用户资料(用户名/头像)
@rpc("any_peer", "reliable")
func send_profile(info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != client_peer_id:
		return
	enemy_info = info
	_update_player_badges()


# ==================== 联机状态同步(主机权威) ====================
# 走子、六面骰、主动技能(愚者/女祭司/魔术师/皇后/皇帝/隐者/死亡/战车等)
# 都会改变棋盘,主机在每次变更后广播完整对局状态,客户端直接采用,保证双方一致。

# 序列化完整对局状态(纯 JSON 安全数据,用于 RPC 传输)
func _state_to_data() -> Dictionary:
	var caps: Array = []
	for rec in captured_history:
		caps.append({
			"side": rec["side"], "type": rec["type"],
			"pos": [rec["pos"].x, rec["pos"].y],
			"birth_pos": [rec["birth_pos"].x, rec["birth_pos"].y],
		})
	var hidden: Array = []
	for pos in hidden_pieces:
		hidden.append([pos.x, pos.y, int(hidden_pieces[pos])])
	var h_turns: Array = []
	for pos in hidden_turns:
		h_turns.append([pos.x, pos.y, int(hidden_turns[pos])])
	var cds := {}
	for s in skill_cd:
		cds[str(s)] = skill_cd[s].duplicate()
	return {
		"board": _board_to_json(board),
		"turn": turn,
		"phase": phase,
		"winner": winner,
		"in_check": in_check,
		"turn_counts": {"0": turn_counts[0], "1": turn_counts[1]},
		"actions_left": actions_left,
		"first_moved": [first_moved.x, first_moved.y],
		"free_retreat_used": free_retreat_used,
		"skill_cd": cds,
		"captured_history": caps,
		"revive_count": {"0": revive_count[0], "1": revive_count[1]},
		"queen_charge": {"0": queen_charge[0], "1": queen_charge[1]},
		"extra_turn": {"0": extra_turn[0], "1": extra_turn[1]},
		"suicide_mark": {} if suicide_mark.is_empty() else {"pos": [suicide_mark["pos"].x, suicide_mark["pos"].y], "side": suicide_mark["side"]},
		"hidden_pieces": hidden,
		"hidden_turns": h_turns,
		"invincible_side": invincible_side,
		"invincible_side_turns": invincible_side_turns,
		"extra_move": {"0": extra_move[0], "1": extra_move[1]},
		"hermit_pending": hermit_pending,
		"hermit_active": hermit_active,
		"controlled_piece": {} if controlled_piece.is_empty() else {"pos": [controlled_piece["pos"].x, controlled_piece["pos"].y], "owner": controlled_piece["owner"]},
		"disabled_skills": {"0": disabled_skills[0], "1": disabled_skills[1]},
		"last_eat": {"side": last_eat["side"], "type": last_eat["type"]},
		"emo2_turns": {"0": emo2_turns[0], "1": emo2_turns[1]},
		"emo2_type": {"0": emo2_type[0], "1": emo2_type[1]},
		"star2_charge": {"0": star2_charge[0], "1": star2_charge[1]},
		"all_hidden_turns": {"0": all_hidden_turns[0], "1": all_hidden_turns[1]},
		"skip_next_turn": {"0": skip_next_turn[0], "1": skip_next_turn[1]},
		"perks_red": perks_red,
		"perks_black": perks_black,
		"invincible_piece": [invincible_piece.x, invincible_piece.y],
		"invincible_piece_side": invincible_piece_side,
		"invincible_piece_turns": invincible_piece_turns,
		"counter_side": counter_side,
		"siwang_charge": {"0": siwang_charge[0], "1": siwang_charge[1]},
		"lianren2_charge": {"0": lianren2_charge[0], "1": lianren2_charge[1]},
		"sync_pieces": _sync_pieces_to_data(),
		"controlled_turns": controlled_turns,
		"controlled_all_turns": controlled_all_turns,
		"controlled_all_owner": controlled_all_owner,
		"control_foreign": {"0": control_foreign[0], "1": control_foreign[1]},
		"pope_guarded": _pope_to_data(),
		"pope_countered": _pope2_to_data(),
		"move_history": _moves_to_json(),
	}


func _sync_pieces_to_data() -> Array:
	var arr: Array = []
	for q in sync_pieces:
		arr.append([q.x, q.y])
	return arr


func _pope_to_data() -> Array:
	var arr: Array = []
	for pos in pope_guarded:
		arr.append([pos.x, pos.y])
	return arr


func _pope2_to_data() -> Array:
	var arr: Array = []
	for pos in pope_countered:
		arr.append([pos.x, pos.y])
	return arr


# 用主机广播的数据覆盖本地对局状态
func _apply_state_data(data: Dictionary) -> void:
	board = _board_from_json(data["board"])
	turn = int(data["turn"])
	phase = int(data["phase"])
	winner = int(data["winner"])
	in_check = bool(data["in_check"])
	turn_counts = {0: int(data["turn_counts"]["0"]), 1: int(data["turn_counts"]["1"])}
	actions_left = int(data["actions_left"])
	first_moved = Vector2i(int(data["first_moved"][0]), int(data["first_moved"][1]))
	free_retreat_used = bool(data["free_retreat_used"])
	skill_cd = {}
	for s in data["skill_cd"]:
		skill_cd[int(s)] = {}
		for id in data["skill_cd"][s]:
			skill_cd[int(s)][id] = int(data["skill_cd"][s][id])
	captured_history = []
	for rec in data["captured_history"]:
		captured_history.append({
			"side": int(rec["side"]), "type": int(rec["type"]),
			"pos": Vector2i(int(rec["pos"][0]), int(rec["pos"][1])),
			"birth_pos": Vector2i(int(rec["birth_pos"][0]), int(rec["birth_pos"][1])),
		})
	revive_count = {0: int(data["revive_count"]["0"]), 1: int(data["revive_count"]["1"])}
	queen_charge = {0: int(data.get("queen_charge", {}).get("0", 0)), 1: int(data.get("queen_charge", {}).get("1", 0))}
	extra_turn = {0: bool(data["extra_turn"]["0"]), 1: bool(data["extra_turn"]["1"])}
	if data["suicide_mark"].is_empty():
		suicide_mark = {}
	else:
		var sm = data["suicide_mark"]
		suicide_mark = {"pos": Vector2i(int(sm["pos"][0]), int(sm["pos"][1])), "side": int(sm["side"])}
	hidden_pieces = {}
	for h in data["hidden_pieces"]:
		hidden_pieces[Vector2i(int(h[0]), int(h[1]))] = int(h[2])
	hidden_turns = {}
	for ht in data.get("hidden_turns", []):
		hidden_turns[Vector2i(int(ht[0]), int(ht[1]))] = int(ht[2])
	invincible_side = int(data["invincible_side"])
	invincible_side_turns = int(data.get("invincible_side_turns", 0))
	extra_move = {0: bool(data.get("extra_move", {}).get("0", false)), 1: bool(data.get("extra_move", {}).get("1", false))}
	hermit_pending = bool(data.get("hermit_pending", false))
	hermit_active = bool(data.get("hermit_active", false))
	if data.get("controlled_piece", {}).is_empty():
		controlled_piece = {}
	else:
		var cpi = data["controlled_piece"]
		controlled_piece = {"pos": Vector2i(int(cpi["pos"][0]), int(cpi["pos"][1])), "owner": int(cpi["owner"])}
	disabled_skills = {0: str(data.get("disabled_skills", {}).get("0", "")), 1: str(data.get("disabled_skills", {}).get("1", ""))}
	var le = data.get("last_eat", {})
	last_eat = {"side": int(le.get("side", -1)), "type": int(le.get("type", -1))}
	emo2_turns = {0: int(data.get("emo2_turns", {}).get("0", 0)), 1: int(data.get("emo2_turns", {}).get("1", 0))}
	emo2_type = {0: int(data.get("emo2_type", {}).get("0", -1)), 1: int(data.get("emo2_type", {}).get("1", -1))}
	all_hidden_turns = {0: int(data.get("all_hidden_turns", {}).get("0", 0)), 1: int(data.get("all_hidden_turns", {}).get("1", 0))}
	skip_next_turn = {0: bool(data.get("skip_next_turn", {}).get("0", false)), 1: bool(data.get("skip_next_turn", {}).get("1", false))}
	star2_charge = {0: int(data.get("star2_charge", {}).get("0", 0)), 1: int(data.get("star2_charge", {}).get("1", 0))}
	if data.has("perks_red"):
		perks_red = data["perks_red"]
		perks_black = data["perks_black"]
	var ip = data.get("invincible_piece", [-1, -1])
	invincible_piece = Vector2i(int(ip[0]), int(ip[1]))
	invincible_piece_side = int(data.get("invincible_piece_side", -1))
	invincible_piece_turns = int(data.get("invincible_piece_turns", 0))
	counter_side = int(data.get("counter_side", -1))
	siwang_charge = {0: int(data.get("siwang_charge", {}).get("0", 0)), 1: int(data.get("siwang_charge", {}).get("1", 0))}
	lianren2_charge = {0: int(data.get("lianren2_charge", {}).get("0", 0)), 1: int(data.get("lianren2_charge", {}).get("1", 0))}
	sync_pieces = []
	for q in data.get("sync_pieces", []):
		sync_pieces.append(Vector2i(int(q[0]), int(q[1])))
	controlled_turns = int(data.get("controlled_turns", 0))
	controlled_all_turns = int(data.get("controlled_all_turns", 0))
	controlled_all_owner = int(data.get("controlled_all_owner", -1))
	control_foreign = {0: bool(data.get("control_foreign", {}).get("0", false)), 1: bool(data.get("control_foreign", {}).get("1", false))}
	pope_guarded = {}
	for pg in data.get("pope_guarded", []):
		pope_guarded[Vector2i(int(pg[0]), int(pg[1]))] = true
	pope_countered = {}
	for pc in data.get("pope_countered", []):
		pope_countered[Vector2i(int(pc[0]), int(pc[1]))] = true
	selected = Vector2i(-1, -1)
	moves_cache = []
	free_retreat_targets = []
	# 对局记录同步:以主机 move_history 为准(含双方技能记录)
	if data.has("move_history"):
		move_history = _moves_from_json(data["move_history"])
		_refresh_move_log()
	_update_ui()
	queue_redraw()


# 主机把完整状态广播给客户端(客户端本地用广播覆盖,保证双方棋子一致)
func _broadcast_state() -> void:
	if net_role != "host":
		return
	print("NET: broadcast state turn=", turn, " actions=", actions_left)
	sync_state.rpc(_state_to_data())


@rpc("authority", "reliable")
func sync_state(data: Dictionary) -> void:
	print("NET: client applied state turn=", int(data["turn"]), " actions=", int(data["actions_left"]))
	_apply_state_data(data)


# 客户端 → 主机:请求释放主动技能(客户端是黑方,参数含目标坐标)
@rpc("any_peer", "reliable")
func request_skill(perk_id: String, params: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != client_peer_id:
		return
	if Global.standard_mode or not perks_black.has(perk_id):
		return
	if turn != R.Side.BLACK:
		return
	if actions_left < _turn_action_cap():
		return  # 已落子:技能与落子二选一
	if skill_cd[1].get(perk_id, 0) > 0:
		return
	if perk_id == "huanghou" and queen_charge[1] <= 0:
		return
	if not _is_active_skill(perk_id):
		return
	print("NET: host skill request ", perk_id, " ", params)
	_record_skill(R.Side.BLACK, perk_id)
	_apply_net_skill(perk_id, params)
	_snapshot_last_board()
	_broadcast_state()


# 释放主动技能后消耗本回合:技能与落子二选一
func _consume_turn_after_skill() -> void:
	if actions_left > 0:
		actions_left = 0
		_end_turn()


# 主机执行客户端请求的技能(黑方),带目标参数
func _apply_net_skill(perk_id: String, params: Dictionary) -> void:
	var side := R.Side.BLACK
	match perk_id:
		"nvjisi", "nvjisi2":
			_skill_priestess(perk_id, side)
		"yuzhe", "yuzhe2":
			_skill_fool(perk_id, side)
		"jiezhi", "jiezhi2":
			_skill_temperance(perk_id, side)
		"huanghou", "huanghou2":
			_skill_queen(perk_id, side)
		"mingyun", "mingyun2":
			_skill_wheel(perk_id, side)
		"yinzhe2":
			_skill_hermit(perk_id, side)
		"yinzhe":
			# 隐者(普通):指定两子隐身两回合
			var ha := Vector2i(int(params["a"][0]), int(params["a"][1]))
			var hb := Vector2i(int(params["b"][0]), int(params["b"][1]))
			var pa = board[ha.y][ha.x]
			var pb = board[hb.y][hb.x]
			if pa == null or pa["side"] != side or pb == null or pb["side"] != side or ha == hb:
				return
			_apply_hermit_target(ha, hb, side)
			_apply_skill_cd("yinzhe", side)
			status_label.text = "隐者:指定两子隐身两回合"
			_consume_turn_after_skill()
		"zhengyi2":
			_skill_justice2(side)
		"siwang2":
			_skill_death2(side)
		"xingxing2":
			# 星星逆位:获得 2 蓄势,跳过本回合
			star2_charge[side] += 2
			_apply_skill_cd("xingxing2", side)
			status_label.text = "星星:获得 2 蓄势(可免费移动 2 个兵),跳过本回合"
			_consume_turn_after_skill()
		"moshushi", "moshushi2":
			var a := Vector2i(int(params["a"][0]), int(params["a"][1]))
			var b := Vector2i(int(params["b"][0]), int(params["b"][1]))
			var need_side: int = side if perk_id == "moshushi" else 1 - side
			var pa = board[a.y][a.x]
			var pb = board[b.y][b.x]
			if pa == null or pa["side"] != need_side or pb == null or pb["side"] != need_side:
				return
			# 逆位(交换对方棋子):敌方将/帅不可被交换(权威校验,防作弊)
			if perk_id == "moshushi2" and (pa["type"] == R.Type.KING or pb["type"] == R.Type.KING):
				return
			board[a.y][a.x] = pb
			board[b.y][b.x] = pa
			_apply_skill_cd(perk_id, side)
			status_label.text = "魔术师:两子位置已交换"
			_consume_turn_after_skill()
		"huangdi":
			var pos := Vector2i(int(params["pos"][0]), int(params["pos"][1]))
			var p = board[pos.y][pos.x]
			if p == null or p["side"] != side:
				return
			invincible_piece = pos
			invincible_piece_side = side
			invincible_piece_turns = 3
			_apply_skill_cd("huangdi", side)
			status_label.text = "皇帝:该子无敌(持续3回合)"
			_consume_turn_after_skill()
		"huangdi2":
			var pos := Vector2i(int(params["pos"][0]), int(params["pos"][1]))
			var p = board[pos.y][pos.x]
			if p == null or p["side"] != side:
				return
			suicide_mark = {"pos": pos, "side": side}
			_apply_skill_cd("huangdi2", side)
			status_label.text = "皇帝:标记棋子,被吃时同归于尽"
			_consume_turn_after_skill()
		"siwang":
			var pos := Vector2i(int(params["pos"][0]), int(params["pos"][1]))
			var p = board[pos.y][pos.x]
			if p == null or p["side"] != side:
				return
			if siwang_charge[side] <= 0:
				return
			siwang_charge[side] -= 1
			_destroy_same_type(pos, side)
			_consume_turn_after_skill()
		"diaodiao2":
			# 逆位:跳过本回合,下回合起获得所有对方棋子控制权三回合
			controlled_all_turns = 3
			controlled_all_owner = side
			_apply_skill_cd(perk_id, side)
			status_label.text = "倒吊人:跳过本回合,下回合起控制所有对方棋子三回合"
			_consume_turn_after_skill()
			return
		"diaodiao":
			# 正位:切换操控模式(己方↔非己方),跳过本回合
			control_foreign[side] = not control_foreign[side]
			_apply_skill_cd(perk_id, side)
			status_label.text = "倒吊人:切换为操控%s棋子" % ("非己方" if control_foreign[side] else "己方")
			_consume_turn_after_skill()
		"zhanche", "zhanche2":
			var piece := Vector2i(int(params["piece"][0]), int(params["piece"][1]))
			var landing := Vector2i(int(params["landing"][0]), int(params["landing"][1]))
			# 找与指定子相邻的己方车
			var rook := Vector2i(-1, -1)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var np: Vector2i = piece + d
				var q = board[np.y][np.x] if R.in_board(np) else null
				if q != null and q["side"] == side and q["type"] == R.Type.ROOK:
					rook = np
					break
			if rook.x < 0:
				return
			if perk_id == "zhanche2":
				# 逆位:移动车到相邻子(含敌方)的可落位
				var rook_p = board[rook.y][rook.x]
				if not landing in R.legal_moves(board, piece, perks_red, perks_black):
					return
				board[rook.y][rook.x] = null
				board[landing.y][landing.x] = rook_p
				_apply_skill_cd("zhanche2", side)
				status_label.text = "战车:车已移至相邻子的可落位"
			else:
				var piece_p = board[piece.y][piece.x]
				if piece_p == null or piece_p["side"] != side:
					return
				if not landing in R.legal_moves(board, rook, perks_red, perks_black):
					return
				board[piece.y][piece.x] = null
				board[landing.y][landing.x] = piece_p
				_apply_skill_cd("zhanche", side)
				status_label.text = "战车:棋子已移至车可落位"
			_consume_turn_after_skill()
	queue_redraw()
	# 联机:主机执行技能成功后,广播屏幕中央提醒给两端(含本地,重复调用被 _announce_root 拦截)
	if net_role == "host" and Global.from_lobby:
		notify_skill_used.rpc(perk_id, R.Side.BLACK)


# 主机 → 双方:广播技能释放提醒(屏幕中央大字)
@rpc("authority", "call_local", "reliable")
func notify_skill_used(perk_id: String, side: int) -> void:
	_show_skill_announce(perk_id, side)


# 主机 → 客户端:黑方(客户端)的三选一技能选项(附带技能池)
@rpc("authority", "reliable")
func send_black_draft_options(options: Array, pool: String) -> void:
	if Global.standard_mode:
		return
	Global.perk_pool = pool
	perks_data = Perks.load_perks(pool)
	print("NET: client got black draft options: ", options, " pool=", pool)
	phase = Phase.SKILL_DRAFT
	draft_side = R.Side.BLACK
	draft_round = 0
	draft_options = []
	for o in options:
		draft_options.append(o)
	_update_draft_ui()
	if _has_user_arg("--auto"):
		call_deferred("_auto_pick_client")


# 客户端 → 主机:黑方(客户端)选完技能,上报最终技能
@rpc("any_peer", "reliable")
func send_black_draft_picks(picks: Array) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != client_peer_id:
		return
	if Global.standard_mode:
		return
	perks_black = {}
	for id in picks:
		perks_black[id] = true
	print("NET: host got black picks: ", perks_black.keys())
	draft_black_done = true
	_start_net_game_after_draft()


# 红方(主机)三选一完成
func _host_red_draft_done() -> void:
	draft_red_done = true
	print("NET: host red picks: ", perks_red.keys())
	_start_net_game_after_draft()


# 双方都选完才开局);先选完的一方显示等待对方
func _start_net_game_after_draft() -> void:
	# 红方还在选(黑方刚选完):保持三选一界面,不覆盖,让红方继续选
	if not draft_red_done:
		return
	# 红方已选完但黑方未选完:显示等待对方
	if not draft_black_done:
		_show_net_draft_wait("技能已选完\n\n等待对方选择技能...")
		return
	# 双方技能齐了,发开局数据给客户端并本地开局
	assign_perks.rpc_id(client_peer_id, perks_black, perks_red, Profile.to_net_data())
	_start_net_game()


# 黑方(客户端)三选一完成:把技能上报主机
func _client_black_draft_done() -> void:
	print("NET: client black picks: ", perks_black.keys())
	send_black_draft_picks.rpc_id(1, perks_black.keys())
	_show_net_draft_wait("黑方技能已选完\n\n等待对方选择技能...")


# 联机等待界面(主机等黑方 / 客户端等开局)
func _show_net_draft_wait(text: String) -> void:
	if draft_root != null:
		draft_root.queue_free()
		draft_root = null
	draft_root = Control.new()
	draft_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(draft_root)

	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.1, 0.09, 0.98)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	draft_root.add_child(bg)

	var label := _make_label(text, 26, Color(0.95, 0.85, 0.6))
	label.position = Vector2(0, 220)
	label.size = Vector2(1280, 160)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	draft_root.add_child(label)
	Global.pop_in_layer(draft_root, 0.4)


# 自动化测试:自动三选一(每次选第一张)
func _auto_pick_host() -> void:
	for i in 3:
		_select_draft_option(draft_options[0])


func _auto_pick_client() -> void:
	for i in 3:
		_select_draft_option(draft_options[0])


func _start_net_game() -> void:
	if draft_root != null:
		draft_root.queue_free()
		draft_root = null
	if net_wait_label != null:
		net_wait_label.queue_free()
		net_wait_label = null
	phase = Phase.PLAY
	_setup_board()
	_begin_turn()
	if _has_user_arg("--auto") and net_role == "host":
		call_deferred("_auto_host_move")


# 自动化测试:主机开局自动走一步红棋
func _auto_host_move() -> void:
	if phase != Phase.PLAY or turn != R.Side.RED:
		return
	var mv := _choose_ai_move()
	if not mv.is_empty():
		_try_perform(mv["from"], mv["to"], "move")


func _has_user_arg(prefix: String) -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return true
	return false


# 客户端 → 主机:走子请求(主机权威校验后广播)
@rpc("any_peer", "reliable")
func request_move(from: Vector2i, to: Vector2i, kind: String) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != client_peer_id:
		return
	if turn != R.Side.BLACK:
		return
	if not _validate_move(from, to, kind, R.Side.BLACK):
		print("NET: rejected invalid move from client ", from, " -> ", to, " kind=", kind)
		return
	print("NET: host accepted move ", from, " -> ", to)
	on_move.rpc(from, to, kind)


# 主机 → 双方:广播走子(含主机本地)
@rpc("authority", "call_local", "reliable")
func on_move(from: Vector2i, to: Vector2i, kind: String) -> void:
	print("NET: on_move ", from, " -> ", to, " kind=", kind)
	if kind == "free_retreat":
		_perform_free_retreat(from, to)
	elif kind == "free_elephant":
		_perform_free_elephant(from, to)
	else:
		_perform_move(from, to)


func _try_perform(from: Vector2i, to: Vector2i, kind: String) -> void:
	# 本地:直接应用;主机:校验后广播;客户端:发请求等主机广播
	if net_role == "local":
		if kind == "free_retreat":
			_perform_free_retreat(from, to)
		elif kind == "free_elephant":
			_perform_free_elephant(from, to)
		else:
			_perform_move(from, to)
	elif net_role == "host":
		if not _validate_move(from, to, kind, R.Side.RED):
			return
		on_move.rpc(from, to, kind)
	else:
		request_move.rpc(from, to, kind)
		_clear_selection()


func _validate_move(from: Vector2i, to: Vector2i, kind: String, side: int) -> bool:
	var p = board[from.y][from.x]
	if p == null or side != turn:
		return false
	# 倒吊人逆位:全棋子控制期可移动对方任意棋子(每子每回合一次)
	var all_control: bool = controlled_all_turns > 0 and controlled_all_owner == turn
	var is_controlled: bool = (not controlled_piece.is_empty() and from == controlled_piece.get("pos", Vector2i(-1, -1)) and controlled_piece.get("owner", -1) == turn) or (all_control and p["side"] != side)
	# 倒吊人正位:切换操控模式——只能操控非己方棋子(被操控棋子可吃子)
	var foreign_mode: bool = control_foreign[turn] and p["side"] != side
	if control_foreign[turn]:
		if p["side"] == side:
			return false  # 切换模式下不能操作己方棋子
		if from in _controlled_moved:
			return false  # 每子每回合只能移动一次
	elif p["side"] != side and not is_controlled:
		return false
	# 全控制:每子每回合只能移动一次
	if all_control and p["side"] != side and from in _controlled_moved:
		return false
	# 协同棋子:本回合已免费移动过一次的不能再移动(防无限移动,host 权威校验)
	if from in _sync_moved:
		return false
	if kind == "move":
		var in_legal: bool = to in R.legal_moves(board, from, perks_red, perks_black)
		# 战车(被动·整局):与车相邻的棋子可落至车的可落位;选中车时可落至相邻子(含敌方)的可落位
		if not in_legal:
			in_legal = to in _chariot_boost_moves(from, side)
		if not in_legal:
			return false
		# 全控制/单子控制:被控子不能吃子;倒吊人正位切换模式操控的非己方棋子可以吃子
		if is_controlled and not foreign_mode and board[to.y][to.x] != null:
			return false
		# 正位切换模式:操控的非己方棋子不能吃操控方自己的王(避免自灭/胜负错乱)
		if foreign_mode and board[to.y][to.x] != null and board[to.y][to.x]["type"] == R.Type.KING and board[to.y][to.x]["side"] == side:
			return false
		# 审判逆位:敌方吃我方棋子时,判断"去掉技能后能否吃到";纯规则吃不到(靠技能增强)则禁吃
		if board[to.y][to.x] != null and perks_of(board[to.y][to.x]["side"]).has("shenpan2"):
			var pure_ok := false
			for pure_m in R.legal_moves(board, from, {}, {}):
				if pure_m == to:
					pure_ok = true
					break
			if not pure_ok:
				return false
		# 隐者:隐身的子不能吃子(可移动到空格)
		if hidden_pieces.has(from) and board[to.y][to.x] != null:
			return false
		if board[to.y][to.x] != null:
			var ts: int = board[to.y][to.x]["side"]
			# 审判:己方吃子时无视敌方棋子所携带效果(无敌/保护/恶魔禁吃等)
			var ignores_effect: bool = perks_of(side).has("shenpan")
			if not ignores_effect:
				if to == invincible_piece or invincible_side == ts:
					return false
				if pope_guarded.has(to):
					return false
				if perks_of(ts).has("emo") and last_eat["side"] == side and last_eat["type"] == p["type"]:
					return false
				# 恶魔逆位:被吃方 2 回合内只能被该类型攻击,其他类型攻击无效
				if perks_of(ts).has("emo2") and emo2_turns[ts] > 0 and p["type"] != emo2_type[ts]:
					return false
				if controlled_turns > 0 and is_controlled:
					return false
		return true
	if kind == "free_retreat":
		# 星星:兵无代价移动一格(任意方向,仅空格)
		# 正位:每回合一次;逆位:消耗蓄势
		if p["type"] != R.Type.PAWN:
			return false
		var star_ok: bool = false
		if perks_of(side).has("xingxing") and not free_retreat_used:
			star_ok = true
		elif perks_of(side).has("xingxing2") and star2_charge[side] > 0:
			star_ok = true
		if not star_ok:
			return false
		if board[to.y][to.x] != null:
			return false
		var diff: Vector2i = to - from
		return absi(diff.x) + absi(diff.y) == 1
	if kind == "free_elephant":
		# 月亮逆位:象免费移动到空格
		if p["type"] != R.Type.ELEPHANT:
			return false
		if not (perks_of(side).has("yueliang2")):
			return false
		if board[to.y][to.x] != null:
			return false
		return to in R.legal_moves(board, from, perks_red, perks_black)
	return false


# ==================== 技能选择(开局 3 次三选一) ====================

func _show_skill_draft() -> void:
	phase = Phase.SKILL_DRAFT
	perks_red = {}
	perks_black = {}
	draft_side = R.Side.RED
	draft_round = 0
	draft_options = []
	_draft_next()


func _draft_next() -> void:
	# 生成 3 个选项(排除双方已选)
	var taken := {}
	taken.merge(perks_red)
	taken.merge(perks_black)
	draft_options = Perks.draw_options(3, taken, Global.perk_pool)
	_update_draft_ui()


func _select_draft_option(perk_id: String) -> void:
	if phase != Phase.SKILL_DRAFT:
		return
	if not perk_id in draft_options:
		return
	perks_of(draft_side)[perk_id] = true
	draft_round += 1
	if draft_round >= 3:
		if draft_side == R.Side.RED:
			if net_role == "host":
				# 联机:红方(主机)选完 → 发给黑方(客户端)
				_host_red_draft_done()
				return
			draft_side = R.Side.BLACK
			draft_round = 0
			if Global.game_mode == "ai":
				_auto_pick_black()
			else:
				_draft_next()
		else:
			if net_role == "client":
				# 联机:黑方(客户端)选完 → 上报主机
				_client_black_draft_done()
				return
			_draft_finish()
	else:
		_draft_next()


func _auto_pick_black() -> void:
	# 人机:电脑(黑方)自动随机选 3 个
	for i in 3:
		var taken := {}
		taken.merge(perks_red)
		taken.merge(perks_black)
		var opts := Perks.draw_options(1, taken, Global.perk_pool)
		if opts.is_empty():
			break
		perks_black[opts[0]] = true
	_draft_finish()


func _draft_finish() -> void:
	if draft_root != null:
		draft_root.queue_free()
		draft_root = null
	_start_game()


# ---------------- 四人模式技能 DRAFT(四方各三选一) ----------------

func _show_skill_draft4() -> void:
	phase = Phase.SKILL_DRAFT
	perks4 = {0: {}, 1: {}, 2: {}, 3: {}}
	draft4_side = 0
	draft4_round = 0
	draft4_options = []
	draft4_done = {0: false, 1: false, 2: false, 3: false}
	_draft_selected4 = []
	# 本地四人:先为每方生成 8 个候选(44→32→4组)
	_four_draft_groups = Perks.build_four_pools(Global.perk_pool)
	_draft_next4()


func _draft_next4() -> void:
	# 本地四人:当前方从预生成的 4 组中取自己那组(8 个)
	if not _four_draft_groups.is_empty() and draft4_side < _four_draft_groups.size():
		draft4_options = _four_draft_groups[draft4_side]
	else:
		var taken := {}
		for side in 4:
			taken.merge(perks4[side])
		draft4_options = Perks.draw_options(3, taken, Global.perk_pool)
	_draft_selected4 = []
	_update_draft_ui()


# 四人:确认选择(本地四方 / 联机提交)
func _confirm_draft4() -> void:
	if phase != Phase.SKILL_DRAFT:
		return
	if _draft_selected4.size() != 3:
		_show_status4("请选择 3 个技能(当前 %d 个)" % _draft_selected4.size())
		return
	var side := draft4_side
	perks4[side] = {}
	for id in _draft_selected4:
		perks4[side][id] = true
	four_draft_picks[side] = _draft_selected4.duplicate()
	draft4_done[side] = true
	if Global.from_lobby and net_role != "local":
		if net_role == "client":
			send_four_draft_picks.rpc_id(1, side, four_draft_picks[side])
			_show_net_draft_wait4("技能已选完\n\n等待其他玩家选择...")
		else:
			# 主机选完:显示等待,等所有客户端上报
			_show_net_draft_wait4("技能已选完\n\n等待其他玩家选择...")
			_check_four_draft_done()
		return
	# 本地四人:切下家
	draft4_side += 1
	if draft4_side >= 4:
		_draft_finish4()
		return
	draft4_round = 0
	_draft_next4()


func _select_draft_option4(perk_id: String) -> void:
	if phase != Phase.SKILL_DRAFT:
		return
	if not perk_id in draft4_options:
		return
	perks4[draft4_side][perk_id] = true
	four_draft_picks[draft4_side].append(perk_id)
	draft4_round += 1
	if draft4_round >= 3:
		draft4_done[draft4_side] = true
		if Global.from_lobby and net_role != "local":
			# 联机:上报主机,等开局广播
			if net_role == "client":
				send_four_draft_picks.rpc_id(1, draft4_side, four_draft_picks[draft4_side])
				_show_net_draft_wait4("技能已选完\n\n等待其他玩家选择...")
			else:
				# 主机自己选完
				_check_four_draft_done()
			return
		draft4_side += 1
		if draft4_side >= 4:
			_draft_finish4()
			return
		draft4_round = 0
		_draft_next4()
	else:
		_draft_next4()


func _draft_finish4() -> void:
	if draft_root != null:
		draft_root.queue_free()
		draft_root = null
	_start_four_game()


func _auto_pick_four() -> void:
	# 自动化:四方各自动选第一张
	for i in 12:
		if phase != Phase.SKILL_DRAFT:
			return
		if draft4_options.is_empty():
			return
		_select_draft_option4(draft4_options[0])


func _start_four_game() -> void:
	phase = Phase.PLAY
	board = R.make_board4()
	_apply_four_skills_setup()
	_refresh_perk_panels4()
	in_check4 = {0: false, 1: false, 2: false, 3: false}
	_prev_check4 = {0: false, 1: false, 2: false, 3: false}
	# 愚者·逆位:开局无充能(满 CD,需 16 回合充能)
	for s in 4:
		if perks4[s].has("yuzhe2"):
			skill_cd4[s]["yuzhe2"] = 16
	_begin_turn4()
	_update_status4()
	queue_redraw()
	if net_role == "host" and Global.from_lobby:
		_broadcast_state4()


# 塔(普通):四人兵线补充兵(黑y3 红y13 绿x3 蓝x13)
func _add_reinforcement4(side: int, count: int) -> void:
	var line := _pawn_line4(side)
	var added := 0
	var n := board.size()
	for i in n:
		if added >= count:
			break
		var pos := _line_pos4(side, i)
		if board[pos.y][pos.x] == null:
			board[pos.y][pos.x] = R.make_piece(side, R.Type.PAWN)
			added += 1


func _remove_all_pawns4(side: int) -> void:
	for r in board.size():
		for c in board[r].size():
			var p = board[r][c]
			if p != null and p["side"] == side and p["type"] == R.Type.PAWN:
				board[r][c] = null


# 四人:该方兵线坐标(黑y3 / 红y13 / 绿x3 / 蓝x13),i 为线上序号
func _line_pos4(side: int, i: int) -> Vector2i:
	match side:
		1: return Vector2i(4 + i, 3)
		0: return Vector2i(4 + i, 13)
		2: return Vector2i(3, 4 + i)
		3: return Vector2i(13, 4 + i)
	return Vector2i(4 + i, 3)


func _pawn_line4(side: int) -> int:
	return 3 if side == 1 else (13 if side == 0 else 3)


func _update_draft_ui() -> void:
	if draft_root != null:
		# queue_free 延迟释放,避免在技能卡点击信号回调中立即 free 导致崩溃
		draft_root.queue_free()
		draft_root = null
	# 首次进入选卡界面弹入;选卡刷新重建不重复弹入
	var first_show := not _draft_ui_shown
	_draft_ui_shown = true
	draft_root = Control.new()
	draft_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(draft_root)

	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.1, 0.09, 0.98)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	draft_root.add_child(bg)

	var cur_side: int = draft4_side if four_mode else draft_side
	var cur_round: int = draft4_round if four_mode else draft_round
	var cur_opts: Array = draft4_options if four_mode else draft_options
	var side_name := _draft_side_name(cur_side)

	if four_mode and cur_opts.size() >= 8:
		# 四人:8 卡 4×2 排列,点击选中/取消,确认按钮提交
		var picked: Array = _draft_selected4
		# 抬头:技能选择 x/3(每选一个 +1)
		var title4 := _make_label("技能选择 %d/3" % picked.size(), 36, Color(0.95, 0.85, 0.6))
		title4.position = Vector2(0, 46)
		title4.size = Vector2(1280, 44)
		title4.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		draft_root.add_child(title4)
		for i in cur_opts.size():
			var id: String = cur_opts[i]
			var info: Dictionary = perks_data[id]
			var card := PerkCard.new()
			var is_sel: bool = id in picked
			card.setup(id, cur_side, info["name"], info.get("tip", ""), info["desc"], _font(), true, 230.0)
			card.position = Vector2(160 + (i % 4) * 245, 140 + (i / 4) * 210)
			card.size = Vector2(230, 120)
			card.selected = is_sel
			card._refresh_style(true, 230.0)
			card.clicked.connect(func(pid: String, _s: int):
				if pid in _draft_selected4:
					_draft_selected4.erase(pid)
				else:
					if _draft_selected4.size() >= 3:
						_show_status4("最多选择 3 个技能")
						return
					_draft_selected4.append(pid)
				_update_draft_ui()
			)
			draft_root.add_child(card)
		# 确认按钮
		var confirm := _make_button("确认选择", Vector2(1280 / 2 - 120, 140 + 2 * 210 + 20), Vector2(240, 52))
		confirm.pressed.connect(_confirm_draft4)
		draft_root.add_child(confirm)
		var hint := _make_label("点击技能卡选中/取消,选满 3 个后点确认", 16, Color(0.85, 0.82, 0.75))
		hint.position = Vector2(0, 140 + 2 * 210 + 80)
		hint.size = Vector2(1280, 24)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		draft_root.add_child(hint)
		if first_show:
			Global.pop_in_layer(draft_root)
		return

	# 双人:旧标题
	var title := _make_label("技能选择 — %s 第 %d/3 轮" % [side_name, cur_round + 1], 36, Color(0.95, 0.85, 0.6))
	title.position = Vector2(0, 60)
	title.size = Vector2(1280, 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	draft_root.add_child(title)

	# 双人:3 张选项卡
	for i in cur_opts.size():
		var id: String = cur_opts[i]
		var info: Dictionary = perks_data[id]
		var card := PerkCard.new()
		card.setup(id, cur_side, info["name"], info.get("tip", ""), info["desc"], _font(), true, 250.0)
		card.position = Vector2(240 + i * 270, 240)
		card.size = Vector2(250, 100)
		card.clicked.connect(func(pid: String, _s: int):
			if four_mode:
				_select_draft_option4(pid)
			else:
				_select_draft_option(pid)
		)
		draft_root.add_child(card)

	# 双方/四方已选技能
	var info_label: Label
	if four_mode:
		var texts4: Array[String] = []
		for side in [1, 0, 2, 3]:
			texts4.append("%s已选: %s" % [SIDE_NAMES4[side], _selected_names4(side)])
		info_label = _make_label("\n".join(texts4), 14, Color(0.85, 0.82, 0.75))
	else:
		info_label = _make_label("红方已选: " + _selected_names(R.Side.RED) + "\n黑方已选: " + _selected_names(R.Side.BLACK), 15, Color(0.85, 0.82, 0.75))
	info_label.position = Vector2(0, 420)
	info_label.size = Vector2(1280, 60)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	draft_root.add_child(info_label)
	if first_show:
		Global.pop_in_layer(draft_root)


func _selected_names(side: int) -> String:
	var names: Array[String] = []
	for id in perks_of(side):
		names.append(perks_data[id]["name"])
	if names.is_empty():
		return "无"
	return "、".join(names)


func _selected_names4(side: int) -> String:
	var names: Array[String] = []
	for id in perks4[side]:
		names.append(perks_data[id]["name"])
	if names.is_empty():
		return "无"
	return "、".join(names)


func _draft_side_name(side: int) -> String:
	if four_mode:
		return SIDE_NAMES4[side]
	return "红方" if side == R.Side.RED else "黑方"


func _start_game() -> void:
	if draft_root != null:
		draft_root.queue_free()
		draft_root = null
	current_slot = _pick_free_slot()
	phase = Phase.PLAY
	_setup_board()
	_snapshot_initial()
	_auto_save()
	# 愚者·逆位:开局无充能(满 CD,需 16 回合充能)
	for s in [0, 1]:
		if perks_of(s).has("yuzhe2"):
			skill_cd[s]["yuzhe2"] = 16
	_begin_turn()


# 新对局自动分配到第一个空槽;槽位全满则用槽 1
func _pick_free_slot() -> int:
	for i in range(1, SLOT_COUNT + 1):
		if not FileAccess.file_exists(_save_path(i)):
			return i
	return 1


func _setup_board() -> void:
	board = R.make_board()
	if perks_of(R.Side.RED).has("ta"):
		_add_reinforcement(R.Side.RED, 4)
	if perks_of(R.Side.BLACK).has("ta"):
		_add_reinforcement(R.Side.BLACK, 4)
	# 塔(进阶):开局失去所有兵
	if perks_of(R.Side.RED).has("ta2"):
		_remove_all_pawns(R.Side.RED)
	if perks_of(R.Side.BLACK).has("ta2"):
		_remove_all_pawns(R.Side.BLACK)
	queue_redraw()


# 塔(进阶):移除该方所有兵
func _remove_all_pawns(side: int) -> void:
	for r in R.ROWS:
		for c in R.COLS:
			var p = board[r][c]
			if p != null and p["side"] == side and p["type"] == R.Type.PAWN:
				board[r][c] = null


func _add_reinforcement(side: int, count: int) -> void:
	# 团结:在兵线空位上补充 count 枚兵(兵线满则停止)
	var row := 6 if side == R.Side.RED else 3
	var added := 0
	for c in R.COLS:
		if added >= count:
			break
		if board[row][c] == null:
			board[row][c] = R.make_piece(side, R.Type.PAWN)
			added += 1


# ==================== 回合状态机 ====================

func perks_of(side: int) -> Dictionary:
	return perks_red if side == R.Side.RED else perks_black


# 游戏感知的将军判定:考虑恶魔(禁同类型连续吃)/隐身(隐身子不能吃)/无敌(王不可被吃)
func _is_in_check_board(b: Array, side: int) -> bool:
	var king := R.find_king(b, side)
	if king.x < 0:
		return false
	if side == invincible_side or pope_guarded.has(king):
		return false  # 王无敌(含教皇保护):不可被吃,不算将军
	var enemy := 1 - side
	for r in R.ROWS:
		for c in R.COLS:
			var pos := Vector2i(c, r)
			var p = b[r][c]
			if p == null or p["side"] != enemy:
				continue
			if hidden_pieces.has(pos):
				continue  # 隐身的子不能吃子,不构成将军
			if perks_of(side).has("emo") and last_eat["side"] == enemy and last_eat["type"] == p["type"]:
				continue  # 恶魔:敌方同类型子被禁吃,不构成将军
			if king in R.raw_moves(b, pos, perks_red, perks_black):
				return true
	return false


# 四人:游戏感知的被将判定(自由混战,任意其它方威胁王即算;其它方全体为敌)
# 考虑恶魔(禁同类型连续吃)/隐身(隐身子不能吃)/无敌(王不可被吃)
func _is_in_check4(board: Array, side: int) -> bool:
	var king := R.find_king(board, side)
	if king.x < 0:
		return false
	if invincible_side4 == side or invincible_piece4 == king or pope_guarded4.has(king):
		return false  # 王无敌(含教皇保护):不可被吃,不算被将
	var perks_arr: Array = [perks4[0], perks4[1], perks4[2], perks4[3]]
	for r in board.size():
		for c in board[r].size():
			var pos := Vector2i(c, r)
			var p = board[r][c]
			if p == null or p["side"] == side:
				continue
			if hidden_pieces4.has(pos):
				continue  # 隐身的子不能吃子,不构成被将
			if perks4[side].has("emo") and last_eat4["side"] == p["side"] and last_eat4["type"] == p["type"]:
				continue  # 恶魔:敌方同类型子被禁吃,不构成被将
			if king in R.raw_moves4(board, pos, perks_arr):
				return true
	return false


# 四人:刷新各方被将状态,并对"刚被将"的一方发出警报(上升沿)
func _refresh_check4() -> void:
	for s in 4:
		var now: bool = _is_in_check4(board, s)
		in_check4[s] = now
		if now and not _prev_check4[s]:
			_show_status4("⚠ %s 被将!" % SIDE_NAMES4[s])
			Global.play_sfx("kill", -4.0)
		_prev_check4[s] = now


# 游戏感知的"是否有合法走法":考虑无敌/象无敌/恶魔/隐身/走后将军
func _has_legal_move_game(side: int) -> bool:
	for r in R.ROWS:
		for c in R.COLS:
			var p = board[r][c]
			if p == null or p["side"] != side:
				continue
			var pos := Vector2i(c, r)
			var self_hidden: bool = hidden_pieces.has(pos)
			for m in R.raw_moves(board, pos, perks_red, perks_black):
				if board[m.y][m.x] != null:
					var ts: int = board[m.y][m.x]["side"]
					if invincible_side == ts or m == invincible_piece:
						continue
					if pope_guarded.has(m):
						continue
					if perks_of(ts).has("emo") and last_eat["side"] == side and last_eat["type"] == p["type"]:
						continue
					if self_hidden:
						continue
				if m == R.find_king(board, 1 - side):
					return true  # 可直接吃王
				var res := R.apply_move(board, pos, m)
				if not _is_in_check_board(res["board"], side):
					return true
	return false


func _begin_turn() -> void:
	turn_counts[turn] += 1
	# 技能状态刷新:冷却递减 / 六面骰 / 隐者与无敌过期 / 节制额外行动
	for id in skill_cd[turn].keys():
		skill_cd[turn][id] = maxi(skill_cd[turn][id] - 1, 0)
	if perks_of(turn).has("shijie"):
		_apply_dice(turn, turn)
	if perks_of(turn).has("shijie2"):
		_apply_dice(turn, 1 - turn)
	# 隐者:下回合(己方回合)移动的子隐身
	hermit_active = hermit_pending
	hermit_pending = false
	# 注:隐者隐身/皇后无敌/皇帝无敌/皇后逆位反制等"持续一回合"效果,改为己方移动后清除(见 _perform_move)
	sync_pieces = []
	_sync_moved = []
	# 倒吊人逆位:全控制回合递减(在控制方回合开始减,生效 3 个己方回合)
	if controlled_all_turns > 0 and controlled_all_owner == turn:
		controlled_all_turns -= 1
		_controlled_moved = []
		if controlled_all_turns <= 0:
			controlled_all_owner = -1
	# 倒吊人正位:切换操控模式(每子每回合限移一次)
	if control_foreign[turn]:
		_controlled_moved = []
	# 恶魔逆位:免疫回合递减(被吃方)
	for s in [0, 1]:
		if emo2_turns[s] > 0:
			emo2_turns[s] -= 1
			if emo2_turns[s] <= 0:
				emo2_type[s] = -1
	# 星星逆位:重置本回合蓄势使用标记
	# 隐者(进阶):己方隐身子每回合每子 10% 概率破隐(逆位持久隐身标记为 side+100)
	if not hidden_pieces.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var reveal: Array[Vector2i] = []
		for pos in hidden_pieces:
			if hidden_pieces[pos] == turn + 100 and rng.randf() < 0.1:
				reveal.append(pos)
		for pos in reveal:
			hidden_pieces.erase(pos)
	# 隐者(进阶):全员隐身倒计时(旧逻辑保留兼容,不再由 yinzhe2 设置)
	if all_hidden_turns[turn] > 0:
		all_hidden_turns[turn] -= 1
		if all_hidden_turns[turn] <= 0:
			_clear_all_hidden()
	# 节制(进阶):本回合被跳过
	if skip_next_turn[turn]:
		skip_next_turn[turn] = false
		status_label.text = "节制:跳过本回合"
		_end_turn()
		return
	# 审判:每回合随机禁用敌方一个主动技能
	_refresh_judgement(turn)
	# 教皇:刷新双方象 5×5 无敌/反制标记(整局生效,不只当前回合方)
	_refresh_pope_guard_all()
	actions_left = _turn_action_cap()
	if extra_turn[turn]:
		extra_turn[turn] = false
		actions_left += 1  # 节制:下回合追加一额外回合
	first_moved = Vector2i(-1, -1)
	free_retreat_used = false
	if not _has_legal_move_game(turn):
		var reason := "checkmate" if _is_in_check_board(board, turn) else "stalemate"
		_win(1 - turn, reason)
		return
	in_check = _is_in_check_board(board, turn)
	_update_ui()
	queue_redraw()
	_maybe_ai()


# 按棋子价值加权随机类型:弱子概率高(兵45%),强子概率低(车5%)
func _random_piece_type(no_pawn_advisor: bool = false) -> int:
	var types := [R.Type.PAWN, R.Type.ROOK, R.Type.HORSE, R.Type.ELEPHANT, R.Type.ADVISOR, R.Type.CANNON]
	var weights := [45, 5, 15, 10, 10, 15]
	if no_pawn_advisor:
		# 女祭司逆位:随机棋子去掉兵和士
		types = [R.Type.ROOK, R.Type.HORSE, R.Type.ELEPHANT, R.Type.CANNON]
		weights = [15, 30, 20, 35]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var total := 0
	for w in weights:
		total += w
	var roll := rng.randi_range(1, total)
	var acc := 0
	for i in weights.size():
		acc += weights[i]
		if roll <= acc:
			return types[i]
	return types[0]


func _apply_dice(side: int, target_side: int) -> void:
	# 世界:每回合 target_side 每个棋子 10% 变为任意棋子(将帅除外)
	if net_role == "client":
		return  # 联机:由主机权威掷骰并广播,客户端不自行随机,否则双方结果不一致
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for r in R.ROWS:
		for c in R.COLS:
			var p = board[r][c]
			if p == null or p["side"] != target_side or p["type"] == R.Type.KING:
				continue
			if rng.randf() < 0.1:
				board[r][c] = R.make_piece(target_side, _random_piece_type())
	_broadcast_state()


# 隐者(进阶):清除全员隐身标记
func _clear_all_hidden() -> void:
	hidden_pieces.clear()
	hidden_turns.clear()
	queue_redraw()


# 教皇:以象为中心的 5×5 范围内棋子获得无敌/反制(正位除象自身,逆位含象自身)
# 注意:本函数只累加 side 方的效果,不清空 dict(调用方应先 _refresh_pope_guard_all)
func _refresh_pope_guard(side: int) -> void:
	var has_pope: bool = perks_of(side).has("jiaohuang")
	var has_pope2: bool = perks_of(side).has("jiaohuang2")
	if not has_pope and not has_pope2:
		return
	for r in R.ROWS:
		for c in R.COLS:
			var p = board[r][c]
			if p == null or p["side"] != side or p["type"] != R.Type.ELEPHANT:
				continue
			var pos := Vector2i(c, r)
			# 以象为中心的 5×5 范围
			for dr in range(-2, 3):
				for dc in range(-2, 3):
					var gpos: Vector2i = pos + Vector2i(dc, dr)
					if not R.in_board(gpos):
						continue
					var gp = board[gpos.y][gpos.x]
					if gpos == pos:
						# 象自身:正位不获得无敌;逆位获得反制
						if has_pope2:
							pope_countered[gpos] = true
						continue
					if gp == null:
						continue
					# 正位:范围内己方棋子无敌(排除象自身及其他象,避免象互保无法被吃)
					if has_pope and gp["side"] == side and gp["type"] != R.Type.ELEPHANT:
						pope_guarded[gpos] = true
					if has_pope2:
						pope_countered[gpos] = true  # 逆位:范围内任意子反制(含敌方)


# 刷新双方教皇效果(先清空再累加,避免多次调用互相覆盖)
func _refresh_pope_guard_all() -> void:
	pope_guarded.clear()
	pope_countered.clear()
	_refresh_pope_guard(R.Side.RED)
	_refresh_pope_guard(R.Side.BLACK)


# 审判:每回合随机禁用敌方一个主动技能
func _refresh_judgement(side: int) -> void:
	disabled_skills[1 - side] = ""
	# 审判逆位:被动效果(敌方不能以技能吃我方棋子),无每回合动作
	if not perks_of(side).has("shenpan"):
		return
	# 审判(正位):随机禁用敌方一个主动技能
	var enemy_active: Array = []
	for id in perks_of(1 - side):
		if _is_active_skill(id):
			enemy_active.append(id)
	if enemy_active.is_empty():
		return
	disabled_skills[1 - side] = enemy_active.pick_random()


func _turn_action_cap() -> int:
	var n := 1
	# 命运之轮:该回合可额外移动一次(下回合生效)
	if extra_move[turn]:
		n += 1
	return n


# "持续一回合"效果在己方移动后清除:
# 隐者隐身(己方标记的)/皇后无敌(己方释放的)/皇帝无敌(己方指定的一子)/皇后逆位反制
# 说明:效果从释放开始覆盖"对方完整回合 + 己方回合直到移动",己方移动一步后到期
func _expire_one_turn_effects(side: int) -> void:
	# 隐者:己方标记的一回合隐身子在己方移动后显形(逆位持久隐身 side+100 不受影响)
	# 隐者(普通)指定两子:标记为 side+200,剩余回合数递减,归零才显形
	var hidden_rm: Array[Vector2i] = []
	for pos in hidden_pieces:
		if hidden_pieces[pos] == side:
			hidden_rm.append(pos)
		elif hidden_pieces[pos] == side + 200:
			hidden_turns[pos] -= 1
			if hidden_turns[pos] <= 0:
				hidden_rm.append(pos)
	for pos in hidden_rm:
		hidden_pieces.erase(pos)
		hidden_turns.erase(pos)
	# 皇后无敌:己方移动后递减(持续2回合)
	if invincible_side == side:
		invincible_side_turns -= 1
		if invincible_side_turns <= 0:
			invincible_side = -1
			invincible_side_turns = 0
	# 皇帝无敌:己方移动后递减(持续3回合)
	if invincible_piece_side == side:
		invincible_piece_turns -= 1
		if invincible_piece_turns <= 0:
			invincible_piece = Vector2i(-1, -1)
			invincible_piece_side = -1
			invincible_piece_turns = 0
	# 皇后逆位反制:己方移动后结束
	if counter_side == side:
		counter_side = -1


func _perform_move(from: Vector2i, to: Vector2i) -> void:
	_record_move(from, to, "move")
	# 移动前先取棋子引用(动画用,避免后续棋盘变化影响)
	var _moving_piece: Dictionary = board[from.y][from.x]
	var res := R.apply_move(board, from, to)
	board = res["board"]
	var captured = res["captured"]
	selected = Vector2i(-1, -1)
	moves_cache = []
	free_retreat_targets = []
	# 移动动画:记录起点/终点像素(与四人一致)
	_move_anims.append({
		"piece": _moving_piece,
		"from_px": _pos_px(from),
		"to_px": _pos_px(to),
		"t": 0.0,
		"dur": 0.22,
	})
	Global.play_sfx("move_chess", -6.0)
	# 隐者:隐身标记跟随棋子移动(己方移动被标记的隐身棋子时)
	# 逆位持久隐身(side+100):移动后立刻破隐;普通指定两子(side+200)跟随移动并转移剩余回合
	if hidden_pieces.has(from):
		var hv: int = hidden_pieces[from]
		if hv >= 100 and hv < 200:
			hidden_pieces.erase(from)
			hidden_turns.erase(from)
		else:
			hidden_pieces[to] = hv
			hidden_pieces.erase(from)
			if hidden_turns.has(from):
				hidden_turns[to] = hidden_turns[from]
				hidden_turns.erase(from)
	# 隐者:下回合移动的子隐身(激活一次)
	if hermit_active and not hidden_pieces.has(to):
		hidden_pieces[to] = turn
		hermit_active = false
	# 倒吊人:控制权棋子走完,控制结束
	if not controlled_piece.is_empty() and from == controlled_piece.get("pos", Vector2i(-1, -1)):
		controlled_piece = {}
		controlled_turns = 0
	# 倒吊人逆位:全控制移动的对方棋子,记录本回合已移动
	if controlled_all_turns > 0 and controlled_all_owner == turn:
		var mover_p = board[to.y][to.x]
		if mover_p != null and mover_p["side"] != turn:
			_controlled_moved.append(from)
	# 倒吊人正位:切换操控模式——记录已移动的非己方棋子(每子每回合限移一次)
	if control_foreign[turn]:
		var mover_f = board[to.y][to.x]
		if mover_f != null and mover_f["side"] != turn:
			_controlled_moved.append(from)
	if captured != null:
		hidden_pieces.erase(to)  # 吃掉目标位置的隐身子时,清除其隐身标记
		hidden_turns.erase(to)
		# 吃子特效:屏幕震动 + 被吃子粒子破碎 + 音效(与四人一致)
		Global.play_sfx("kill", -4.0)
		_shake_time = 0.3
		_shake_strength = 9.0
		var cap_center: Vector2 = _pos_px(to)
		var cap_col: Color = _side_color(captured["side"])
		var crng := RandomNumberGenerator.new()
		crng.randomize()
		for i in 14:
			var cang := crng.randf() * TAU
			var cspd := crng.randf_range(40.0, 140.0)
			_debris.append({
				"pos": cap_center,
				"vel": Vector2(cos(cang), sin(cang)) * cspd,
				"life": crng.randf_range(0.35, 0.6),
				"max": 0.6,
				"size": crng.randf_range(3.0, 6.0),
				"color": cap_col,
			})
		# 恶魔:记录"谁用什么类型吃了"(被吃方有恶魔时,同类型不能连续吃)
		if perks_of(captured["side"]).has("emo") or perks_of(captured["side"]).has("emo2"):
			var atk = board[to.y][to.x]
			last_eat = {"side": turn, "type": atk["type"] if atk != null else -1}
		# 恶魔逆位:被吃方 2 回合内只能被该类型攻击(其他类型免疫)
		if perks_of(captured["side"]).has("emo2"):
			var atk2 = board[to.y][to.x]
			emo2_turns[captured["side"]] = 2
			emo2_type[captured["side"]] = atk2["type"] if atk2 != null else -1
		_handle_capture(captured, to, turn)
		if captured["type"] == R.Type.KING:
			_snapshot_last_board()
			_win(turn)
			return
	# first_moved 记录棋子移动后的新位置,用于"额外回合不能连移同子"检查
	first_moved = to
	# 命运之轮(进阶):协同棋子移动不消耗步数;协同位置跟随棋子移动;记录已免费移动(每回合一次)
	var was_sync: bool = from in sync_pieces
	if not was_sync:
		actions_left -= 1
	else:
		var si := sync_pieces.find(from)
		if si >= 0:
			sync_pieces[si] = to
			_sync_moved.append(to)
	# "持续一回合"效果在己方移动后清除(隐者隐身/皇后无敌/皇帝无敌)
	_expire_one_turn_effects(turn)
	# 记录该步执行后的棋盘(含被动技能效果),供复盘/悔棋还原
	_snapshot_last_board()
	queue_redraw()
	if actions_left <= 0:
		_end_turn()
	else:
		_update_ui()
		_maybe_ai()
	_auto_save()
	_refresh_pope_guard_all()
	if net_role == "host":
		_broadcast_state()


func _handle_capture(captured: Dictionary, captured_pos: Vector2i, attacker_side: int) -> void:
	# 记录被吃子(用于魔术师/生生不息)
	var birth := _birth_pos(captured["side"], captured["type"])
	captured_history.append({"side": captured["side"], "type": captured["type"], "pos": captured_pos, "birth_pos": birth})
	# 反制:被吃时同归于尽(攻击者占据被吃位置,一并移除)
	var victim_side: int = captured["side"]
	var counter_triggered: bool = false
	if suicide_mark.get("pos") == captured_pos and suicide_mark.get("side") == victim_side:
		counter_triggered = true
		suicide_mark = {}
		status_label.text = "皇帝:同归于尽!"
	elif victim_side == counter_side:
		counter_triggered = true
		status_label.text = "皇后:反制,同归于尽!"
	elif pope_countered.has(captured_pos):
		counter_triggered = true
		status_label.text = "教皇:反制,同归于尽!"
	if counter_triggered:
		board[captured_pos.y][captured_pos.x] = null
	# 恋人:己方每被吃 2 子,复活一枚到出生位置
	revive_count[victim_side] += 1
	if perks_of(victim_side).has("lianren") and revive_count[victim_side] % 2 == 0:
		_revive_piece(victim_side)
	# 恋人(逆位):被吃充能(需求 2,使用后其他技能完成冷却/充能)
	if perks_of(victim_side).has("lianren2"):
		lianren2_charge[victim_side] = mini(lianren2_charge[victim_side] + 1, 2)
	# 皇后:己方每被吃 1 子,充能 +1(上限 1;逆位力量可累计至 3 倍)
	var queen_cap := 3 if perks_of(victim_side).has("liliang2") else 1
	if perks_of(victim_side).has("huanghou") or perks_of(victim_side).has("huanghou2"):
		queen_charge[victim_side] = mini(queen_charge[victim_side] + 1, queen_cap)
	# 死亡:己方每被吃 1 子,充能 +1(上限 3;逆位力量可累计至 3 倍)
	var siwang_cap := 9 if perks_of(victim_side).has("liliang2") else 3
	if perks_of(victim_side).has("siwang") or perks_of(victim_side).has("siwang2"):
		siwang_charge[victim_side] = mini(siwang_charge[victim_side] + 1, siwang_cap)


# 恋人(进阶):随机摧毁对方 n 枚棋子(将帅除外)
func _destroy_random_enemy(victim_side: int, n: int) -> void:
	var enemy := 1 - victim_side
	var candidates: Array[Vector2i] = []
	for r in R.ROWS:
		for c in R.COLS:
			var q = board[r][c]
			if q != null and q["side"] == enemy and q["type"] != R.Type.KING:
				candidates.append(Vector2i(c, r))
	candidates.shuffle()
	for i in mini(n, candidates.size()):
		var v: Vector2i = candidates[i]
		board[v.y][v.x] = null
	status_label.text = "恋人:随机摧毁对方 %d 枚棋子" % mini(n, candidates.size())
	queue_redraw()


func _revive_piece(side: int) -> void:
	# 从吃子记录中找该方最近被吃的子,复活到出生位置(空位)
	for i in range(captured_history.size() - 1, -1, -1):
		var rec = captured_history[i]
		if rec["side"] != side:
			continue
		var target := Vector2i(-1, -1)
		if rec["type"] == R.Type.PAWN:
			# 兵:复活到兵线第一个空位
			var prow := 6 if side == R.Side.RED else 3
			for c in R.COLS:
				if board[prow][c] == null:
					target = Vector2i(c, prow)
					break
		else:
			var bp: Vector2i = rec["birth_pos"]
			if bp.x >= 0 and board[bp.y][bp.x] == null:
				target = bp
		if target.x >= 0:
			board[target.y][target.x] = R.make_piece(side, rec["type"])
			var nm: String = R.PIECE_NAMES[rec["type"]] if side == R.Side.RED else R.PIECE_NAMES_BLACK[rec["type"]]
			status_label.text = "生生不息:复活一枚 %s" % nm
			queue_redraw()
			return
	status_label.text = "生生不息:无可复活位置"


func _birth_pos(side: int, type: int) -> Vector2i:
	var row := 9 if side == R.Side.RED else 0
	match type:
		R.Type.ROOK:
			return Vector2i(0, row)
		R.Type.HORSE:
			return Vector2i(1, row)
		R.Type.ELEPHANT:
			return Vector2i(2, row)
		R.Type.ADVISOR:
			return Vector2i(3, row)
		R.Type.CANNON:
			return Vector2i(1, row - 2)
		R.Type.PAWN:
			# 兵线找空位(位置被占则不可复活,由调用方判断)
			return Vector2i(-1, -1)
	return Vector2i(-1, -1)


func _perform_free_retreat(from: Vector2i, to: Vector2i) -> void:
	# 星星:兵无代价移动一格,不消耗行动次数
	_record_move(from, to, "free_retreat")
	var p = board[from.y][from.x]
	board[from.y][from.x] = null
	board[to.y][to.x] = p
	free_retreat_used = true
	# 星星逆位:消耗 1 蓄势(允许连续移动同一兵)
	if perks_of(turn).has("xingxing2") and star2_charge[turn] > 0:
		star2_charge[turn] -= 1
	selected = Vector2i(-1, -1)
	moves_cache = []
	free_retreat_targets = []
	_snapshot_last_board()
	queue_redraw()
	_auto_save()
	_update_ui()


func _perform_free_elephant(from: Vector2i, to: Vector2i) -> void:
	# 月亮逆位:象无代价移动到空格,不消耗行动次数,不结束回合
	_record_move(from, to, "free_elephant")
	var p = board[from.y][from.x]
	board[from.y][from.x] = null
	board[to.y][to.x] = p
	selected = Vector2i(-1, -1)
	moves_cache = []
	free_elephant_targets = []
	_snapshot_last_board()
	queue_redraw()
	_auto_save()
	_update_ui()


# 图鉴演示:悔棋(保存快照后撤回上一步)
func _do_undo() -> void:
	undo_snapshot = _state_to_data()
	undo_snapshot["_move_history"] = _moves_to_json()
	_undo_ai_move()


# 图鉴演示:撤销悔棋(恢复悔棋前状态,含走子记录)
func _do_redo() -> void:
	if undo_snapshot.is_empty():
		return
	if undo_snapshot.has("_move_history"):
		move_history = _moves_from_json(undo_snapshot["_move_history"])
	_apply_state_data(undo_snapshot)
	undo_snapshot = {}
	_refresh_move_log()
	queue_redraw()


func _undo_ai_move() -> void:
	# 人机对局悔棋:回到玩家上一回合开始(移除 AI 步 + 玩家步,从开局快照重放)
	if net_role != "local" or Global.game_mode != "ai" or replay_mode:
		return
	if turn != R.Side.RED or move_history.is_empty():
		return
	# 移除末尾所有 AI(黑)步和玩家(红)步
	var removed := 0
	while not move_history.is_empty() and move_history[-1].get("side", 1) == R.Side.BLACK:
		move_history.pop_back()
		removed += 1
	while not move_history.is_empty() and move_history[-1].get("side", 0) == R.Side.RED:
		move_history.pop_back()
		removed += 1
	if removed == 0:
		return
	# 从开局快照重放剩余走子(有快照的用快照,含技能/被动效果)
	board = _clone_board(initial_snapshot["board"])
	for m in move_history:
		var snap = m.get("board_after")
		if snap != null:
			board = _clone_board(snap)
		elif m.get("kind", "move") == "skill":
			pass  # 旧存档技能记录无快照:保持原棋盘
		else:
			board = R.apply_move(board, m["from"], m["to"])["board"]
	# 重置回合状态(轮到红方,红方开始新回合)
	turn = R.Side.RED
	var max_turn := {0: 0, 1: 0}
	for m in move_history:
		var t: int = m.get("turn", 1)
		var s: int = m.get("side", 0)
		max_turn[s] = maxi(max_turn[s], t)
	turn_counts = {0: max_turn[0], 1: max_turn[1]}
	turn_counts[0] += 1  # 红方开始新回合(等效 _begin_turn 的递增)
	actions_left = _turn_action_cap()
	first_moved = Vector2i(-1, -1)
	free_retreat_used = false
	selected = Vector2i(-1, -1)
	moves_cache = []
	free_retreat_targets = []
	in_check = R.is_in_check(board, turn, perks_red, perks_black)
	_refresh_move_log()
	_update_ui()
	queue_redraw()


func _end_turn() -> void:
	# 命运之轮:额外行动只在本回合生效
	extra_move[turn] = false
	turn = 1 - turn
	_begin_turn()


# ==================== 存档 ====================

func _snapshot_initial() -> void:
	initial_snapshot = {
		"board": _clone_board(board),
		"perks_red": perks_red.duplicate(),
		"perks_black": perks_black.duplicate(),
	}


func _record_move(from: Vector2i, to: Vector2i, kind: String) -> void:
	if replay_mode:
		return
	var p = board[from.y][from.x]
	var side: int = p["side"]
	var name: String = R.PIECE_NAMES[p["type"]] if side == R.Side.RED else R.PIECE_NAMES_BLACK[p["type"]]
	# 记录当前走子方的真实回合序号(速度取胜等加行动技能时,同回合多步共享同一序号)
	move_history.append({"from": from, "to": to, "kind": kind, "side": side, "name": name, "turn": turn_counts[turn], "board_after": null})
	_refresh_move_log()


# 记录技能使用(双人):kind=skill, name=技能名;board_after 由 _snapshot_last_board 补记
func _record_skill(side: int, perk_id: String) -> void:
	if replay_mode:
		return
	var nm: String = perks_data[perk_id]["name"] if perks_data.has(perk_id) else perk_id
	move_history.append({"from": Vector2i(-1, -1), "to": Vector2i(-1, -1), "kind": "skill", "side": side, "name": nm, "turn": turn_counts[side], "board_after": null})
	_refresh_move_log()


# 记录完成后:把当前棋盘快照存入最后一条历史记录(走子/技能都可),供复盘/悔棋还原
func _snapshot_last_board() -> void:
	if replay_mode or move_history.is_empty():
		return
	var last = move_history[-1]
	last["board_after"] = _clone_board(board)


func _refresh_move_log() -> void:
	if move_log_box == null:
		move_log_box = record_box
	if move_log_box == null:
		return
	for child in move_log_box.get_children():
		child.free()
	# 按真实回合分组:红方第 n 回合 → 组 2n-1,黑方第 n 回合 → 组 2n
	var groups: Dictionary = {}
	var order: Array = []
	for i in move_history.size():
		var m = move_history[i]
		var side: int = m.get("side", 0)
		var name: String = m.get("name", "?")
		var t: int = m.get("turn", -1)
		if t < 0:
			t = i / 2 + 1  # 旧存档兜底
		var g: int = t  # 同一回合的红方与黑方步数合并到一行
		var side_name := "红" if side == R.Side.RED else "黑"
		var text: String
		if m.get("kind", "move") == "skill":
			text = "%s方 技能[%s]" % [side_name, name]
		else:
			text = "%s%s %d%d→%d%d" % [side_name, name, m["from"].x, m["from"].y, m["to"].x, m["to"].y]
			if m.get("kind", "move") == "free_retreat":
				text += "退"
		if not groups.has(g):
			groups[g] = []
			order.append(g)
		groups[g].append(text)
	var lines: Array[String] = []
	for idx in order.size():
		lines.append("%d. %s" % [idx + 1, "　".join(groups[order[idx]])])
	for line in lines:
		var l := _make_label(line, 13, Color(0.85, 0.82, 0.75))
		move_log_box.add_child(l)


func _clone_board(b: Array) -> Array:
	return R.clone_board(b)


func _board_to_json(b: Array) -> Array:
	var data: Array = []
	for row in b:
		var r: Array = []
		for p in row:
			r.append(null if p == null else {"side": int(p["side"]), "type": int(p["type"])})
		data.append(r)
	return data


func _board_from_json(data: Array) -> Array:
	var b: Array = []
	for r in data:
		var row: Array = []
		for p in r:
			row.append(null if p == null else {"side": int(p["side"]), "type": int(p["type"])})
		b.append(row)
	return b


func _moves_to_json() -> Array:
	var arr: Array = []
	for m in move_history:
		var entry := {
			"from": [m["from"].x, m["from"].y],
			"to": [m["to"].x, m["to"].y],
			"kind": m["kind"],
			"side": m.get("side", 0),
			"name": m.get("name", "?"),
			"turn": m.get("turn", -1),
		}
		# 技能记录:序列化棋盘快照(复盘还原技能造成的棋盘变化)
		if m.get("kind", "move") == "skill" and m.get("board_after") != null:
			entry["board_after"] = _board_to_json(m["board_after"])
		arr.append(entry)
	return arr


func _moves_from_json(arr: Array) -> Array:
	var moves: Array = []
	for m in arr:
		var entry := {
			"from": Vector2i(int(m["from"][0]), int(m["from"][1])),
			"to": Vector2i(int(m["to"][0]), int(m["to"][1])),
			"kind": m["kind"],
			"side": int(m.get("side", 0)),
			"name": m.get("name", "?"),
			"turn": int(m.get("turn", -1)),
			"board_after": null,
		}
		if m.get("kind", "move") == "skill" and m.has("board_after") and m["board_after"] != null:
			entry["board_after"] = _board_from_json(m["board_after"])
		moves.append(entry)
	return moves


func _save_path(slot: int) -> String:
	return "user://savegame_%d.json" % slot


func _auto_save() -> void:
	# 自动存档:本地对局、非复盘、有开局快照时保存到当前槽位
	if net_role != "local" or replay_mode or initial_snapshot.is_empty():
		return
	_save_game()


func _save_game() -> void:
	var data := {
		"board": _board_to_json(board),
		"perks_red": perks_red,
		"perks_black": perks_black,
		"turn": turn,
		"turn_counts": {"0": turn_counts[0], "1": turn_counts[1]},
		"free_retreat_used": free_retreat_used,
		"actions_left": actions_left,
		"first_moved": [first_moved.x, first_moved.y],
		"move_history": _moves_to_json(),
		"initial_snapshot": {
			"board": _board_to_json(initial_snapshot["board"]),
			"perks_red": initial_snapshot["perks_red"],
			"perks_black": initial_snapshot["perks_black"],
		},
	}
	var f := FileAccess.open(_save_path(current_slot), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _load_game(slot: int) -> bool:
	var path := _save_path(slot)
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data == null:
		return false
	board = _board_from_json(data["board"])
	perks_red = data["perks_red"]
	perks_black = data["perks_black"]
	turn = int(data["turn"])
	turn_counts = {0: int(data["turn_counts"]["0"]), 1: int(data["turn_counts"]["1"])}
	free_retreat_used = bool(data["free_retreat_used"])
	actions_left = int(data["actions_left"])
	first_moved = Vector2i(int(data["first_moved"][0]), int(data["first_moved"][1]))
	move_history = _moves_from_json(data["move_history"])
	initial_snapshot = {
		"board": _board_from_json(data["initial_snapshot"]["board"]),
		"perks_red": data["initial_snapshot"]["perks_red"],
		"perks_black": data["initial_snapshot"]["perks_black"],
	}
	current_slot = slot
	return true


# ==================== 复盘 ====================

func _start_replay() -> void:
	if move_history.is_empty():
		return
	replay_mode = true
	replay_index = 0
	replay_auto = false
	replay_timer = 0.0
	# 隐藏结果界面,避免与复盘遮罩叠加成两层黑
	if result_root != null:
		result_root.visible = false
	_build_replay_ui()
	_apply_replay()


func _build_replay_ui() -> void:
	replay_root = Control.new()
	replay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(replay_root)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.12, 0.32)  # 浅色遮罩,复盘时棋盘清晰可见
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	replay_root.add_child(bg)

	replay_label = _make_label("", 22, Color(0.95, 0.85, 0.6))
	replay_label.position = Vector2(0, 40)
	replay_label.size = Vector2(1280, 34)
	replay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	replay_root.add_child(replay_label)

	var prev := _make_button("◀ 上一步", Vector2(430, 470), Vector2(130, 44))
	prev.pressed.connect(_replay_prev)
	replay_root.add_child(prev)

	var next := _make_button("下一步 ▶", Vector2(580, 470), Vector2(130, 44))
	next.pressed.connect(_replay_next)
	replay_root.add_child(next)

	var auto := _make_button("自动播放", Vector2(730, 470), Vector2(130, 44))
	auto.pressed.connect(_toggle_replay_auto)
	replay_root.add_child(auto)

	var exit := _make_button("退出复盘", Vector2(560, 535), Vector2(160, 44))
	exit.pressed.connect(_exit_replay)
	replay_root.add_child(exit)
	Global.pop_in_layer(replay_root)


func _apply_replay() -> void:
	replay_board = _clone_board(initial_snapshot["board"])
	for i in replay_index:
		var m = move_history[i]
		var snap = m.get("board_after")
		if snap != null:
			# 优先用执行后的棋盘快照(含技能/被动效果)
			replay_board = _clone_board(snap)
		elif m.get("kind", "move") == "skill":
			pass  # 旧存档技能记录无快照:保持原棋盘
		else:
			replay_board = R.apply_move(replay_board, m["from"], m["to"])["board"]
	if replay_label != null:
		replay_label.text = "复盘 第 %d / %d 步" % [replay_index, move_history.size()]
	queue_redraw()


func _replay_next() -> void:
	if replay_index < move_history.size():
		replay_index += 1
		_apply_replay()


func _replay_prev() -> void:
	if replay_index > 0:
		replay_index -= 1
		_apply_replay()


func _toggle_replay_auto() -> void:
	replay_auto = not replay_auto


func _exit_replay() -> void:
	replay_mode = false
	replay_auto = false
	if replay_root != null:
		var root := replay_root
		replay_root = null
		Global.pop_out(root, 0.3, func(): root.queue_free())
	if result_root != null:
		result_root.visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if replay_mode and replay_auto and replay_index < move_history.size():
		replay_timer += delta
		if replay_timer >= 0.5:
			replay_timer = 0.0
			_replay_next()
	# 轮到走子:头像框高亮发光(正弦脉动)
	_glow_time += delta
	_update_badge_glow()
	# 断线重连:定时尝试
	if _reconnecting:
		_reconnect_timer += delta
		if _reconnect_timer >= _reconnect_interval:
			_reconnect_timer = 0.0
			_try_reconnect()
	# 四人:技能提示显示 1 秒后恢复回合显示
	if four_mode and status_label != null and _status4_until > 0.0:
		if Time.get_ticks_msec() / 1000.0 >= _status4_until:
			_status4_until = 0.0
			_update_status4()
	# 自己回合:"你的回合"呼吸(透明度正弦脉动)
	if four_mode and _my_turn_breath4 and status_label != null and _status4_until <= 0.0:
		var pulse := 0.55 + 0.45 * sin(_glow_time * 4.0)
		status_label.modulate.a = pulse
	# 棋子移动动画推进
	if not _move_anims.is_empty():
		for i in range(_move_anims.size() - 1, -1, -1):
			_move_anims[i]["t"] += delta
			if _move_anims[i]["t"] >= _move_anims[i]["dur"]:
				_move_anims.remove_at(i)
		queue_redraw()
	# 吃子粒子推进
	if not _debris.is_empty():
		var grav := 260.0
		for i in range(_debris.size() - 1, -1, -1):
			var d = _debris[i]
			d["vel"].y += grav * delta
			d["pos"] += d["vel"] * delta
			d["life"] -= delta
			if d["life"] <= 0.0:
				_debris.remove_at(i)
		queue_redraw()
	# 屏幕震动衰减
	if _shake_time > 0.0:
		_shake_time -= delta
		var prog: float = clampf(_shake_time / 0.3, 0.0, 1.0)
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		position = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * _shake_strength * prog
	else:
		position = Vector2.ZERO


func _win(side: int, reason := "") -> void:
	phase = Phase.OVER
	winner = side
	var text := "红方胜利!" if side == R.Side.RED else "黑方胜利!"
	if reason == "checkmate":
		text += "\n(将死:被将军且无法应对)"
	elif reason == "stalemate":
		text += "\n(困毙:无子可走)"
	else:
		text += "\n(吃掉对方王!)"
	status_label.text = text
	_show_result()


func _show_result() -> void:
	result_root = Control.new()
	result_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(result_root)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.12, 0.9)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_root.add_child(bg)
	var title := _make_label("红方胜利!" if winner == R.Side.RED else "黑方胜利!", 40, Color(0.95, 0.85, 0.6))
	title.position = Vector2(0, 120)
	title.size = Vector2(1280, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_root.add_child(title)
	var again := _make_button("再来一局(重新抽卡)", Vector2(540, 240), Vector2(200, 52))
	again.pressed.connect(func():
		Global.clear_reconnect_info()
		if net_role == "local":
			get_tree().reload_current_scene()
		else:
			# 联机局:回到主菜单重新建房/加入
			Global.change_scene_with_fade("res://scenes/main.tscn")
	)
	result_root.add_child(again)
	# 复盘本局(有走子记录时)
	if not move_history.is_empty():
		var replay_btn := _make_button("复盘本局", Vector2(540, 310), Vector2(200, 52))
		replay_btn.pressed.connect(_start_replay)
		result_root.add_child(replay_btn)
	var menu := _make_button("返回菜单", Vector2(540, 380), Vector2(200, 52))
	menu.pressed.connect(func():
		Global.clear_reconnect_info()
		if Global.demo_perk != "":
			Global.demo_perk = ""
			Global.change_scene_with_fade("res://scenes/manual.tscn")
		else:
			Global.change_scene_with_fade("res://scenes/main.tscn")
	)
	result_root.add_child(menu)
	Global.pop_in_layer(result_root)


func _update_ui() -> void:
	var side_name := "红方" if turn == R.Side.RED else "黑方"
	var text := "%s回合" % side_name
	if in_check:
		text += "  ⚠ 将军!"
	if actions_left > 1:
		text += "  (本回合剩余 %d 次行动)" % actions_left
	status_label.text = text
	status_label.modulate = _side_color(turn)
	_refresh_perk_panels()


func _refresh_perk_panels() -> void:
	# 我方技能面板 + 敌方技能面板 分开刷新
	# 注意:必须用 queue_free 而非 free —— 释放技能后回合切换会触发这里重建面板,
	# 而当前点击的技能卡仍在处理 gui_input,直接 free 会报"locked object can't be freed"
	if self_perk_list_box != null:
		for child in self_perk_list_box.get_children():
			# 先移除再延迟释放:避免旧卡在帧末前与新卡重叠显示(技能卡翻倍)
			self_perk_list_box.remove_child(child)
			child.queue_free()
		_add_perk_cards(self_perk_list_box, _self_side(), true)
	if enemy_perk_list_box != null:
		for child in enemy_perk_list_box.get_children():
			enemy_perk_list_box.remove_child(child)
			child.queue_free()
		_add_perk_cards(enemy_perk_list_box, 1 - _self_side(), false)


func _self_side() -> int:
	# 联机按己方阵营;本地(双人/人机)红方为视角
	if net_role == "local":
		return R.Side.RED
	return own_side


func _add_perk_cards(box: VBoxContainer, side_id: int, is_self: bool) -> void:
	if perks_of(side_id).is_empty():
		# 标准模式或无技能:显示提示
		var l := _make_label("无技能(标准模式)", 13, Color(0.6, 0.58, 0.54))
		box.add_child(l)
		return
	for id in perks_of(side_id):
		# 跳过内部标记键(正义逆位的炮隔子标记不是真实技能)
		if str(id).begins_with("_"):
			continue
		var info: Dictionary = perks_data[id]
		var tip: String = info.get("tip", "")
		# 充能进度:皇后/死亡用充能值(逆位力量可累计至3倍上限),星星逆位显示蓄势,主动技能显示剩余冷却
		var prog := ""
		if id == "huanghou":
			var qcap := 3 if perks_of(side_id).has("liliang2") else 1
			prog = "充能 %d/%d" % [queen_charge[side_id], qcap]
		elif id == "siwang":
			var scap := 9 if perks_of(side_id).has("liliang2") else 3
			prog = "充能 %d/%d" % [siwang_charge[side_id], scap]
		elif id == "lianren2":
			prog = "充能 %d/2" % lianren2_charge[side_id]
		elif id == "xingxing2":
			prog = "蓄势 %d" % star2_charge.get(side_id, 0)
		if _is_active_skill(id) and prog.is_empty():
			var cd_left: int = int(skill_cd.get(side_id, {}).get(id, 0))
			if cd_left > 0:
				prog = "冷却 %d" % cd_left
		if not prog.is_empty():
			tip += "  [%s]" % prog
		var card := PerkCard.new()
		card.setup(id, side_id, info["name"], tip, info["desc"], _font(), is_self, 210.0)
		card.clicked.connect(_on_perk_clicked)
		box.add_child(card)


func _on_perk_clicked(perk_id: String, side: int) -> void:
	if phase != Phase.PLAY:
		return
	if side != _self_side():
		status_label.text = "只能使用己方技能"
		return
	if not _is_active_skill(perk_id):
		status_label.text = "[%s] 被动技能,整局自动生效" % perks_data[perk_id]["name"]
		return
	if turn != side:
		status_label.text = "只能在己方回合使用技能"
		return
	# 平衡性:每回合主动技能与落子二选一,已落子则不能再放技能
	if actions_left < _turn_action_cap():
		status_label.text = "本回合已落子,技能与落子二选一"
		return
	# 审判:被禁用的技能不可释放
	if disabled_skills[side] == perk_id:
		status_label.text = "[%s] 被审判禁用,本回合不可使用" % perks_data[perk_id]["name"]
		return
	var cd: int = skill_cd[side].get(perk_id, 0)
	if cd > 0:
		status_label.text = "[%s] 冷却中(剩余 %d 回合)" % [perks_data[perk_id]["name"], cd]
		return
	# 皇后:被吃充能,无充能不可释放
	if perk_id == "huanghou" and queen_charge[side] <= 0:
		status_label.text = "[皇后] 充能中:己方每被吃 1 子充能 1 点"
		return
	if net_role == "client":
		# 联机客户端:主动技能由主机权威执行并广播,这里只发请求
		if _is_targeting_skill(perk_id):
			# 目标型技能(皇帝/隐者/死亡/战车):进入本地目标选择,选完再上报
			_activate_skill(perk_id, side)
		else:
			request_skill.rpc_id(1, perk_id, {})
			status_label.text = "[%s] 技能已发送,等待对方确认" % perks_data[perk_id]["name"]
		return
	_activate_skill(perk_id, side)
	if net_role == "host":
		_broadcast_state()


func _is_targeting_skill(perk_id: String) -> bool:
	return perk_id in ["moshushi", "moshushi2", "huangdi", "huangdi2", "siwang", "yinzhe"]


func _is_active_skill(perk_id: String) -> bool:
	var tip: String = perks_data[perk_id].get("tip", "")
	return tip.begins_with("主动")


func _skill_cd_value(perk_id: String) -> int:
	var tip: String = perks_data[perk_id].get("tip", "")
	var digits := ""
	for ch in tip:
		if ch.is_valid_int():
			digits += ch
	return int(digits) if not digits.is_empty() else 0


func _apply_skill_cd(perk_id: String, side: int) -> void:
	var cd := _skill_cd_value(perk_id)
	if cd <= 0:
		return
	if perks_of(side).has("liliang"):
		cd = maxi(cd - 2, 0)  # 力量:我方主动技能冷却-2
	# 注:逆位力量已改为"充能可累计至3倍上限",不再影响敌方冷却
	if cd > 0:
		skill_cd[side][perk_id] = cd


# 全局技能释放提醒:屏幕中央大字提示(双人/四人通用)
var _announce_root: Control
var _announce_tween: Tween


func _show_skill_announce(perk_id: String, side: int) -> void:
	if ui == null or _announce_root != null:
		return
	var nm: String = perks_data[perk_id]["name"] if perks_data.has(perk_id) else perk_id
	var who: String
	if four_mode:
		who = SIDE_NAMES4[side]
	else:
		who = "红方" if side == R.Side.RED else "黑方"
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	_announce_root = root
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1, 0.35)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var label := _make_label("", 40, Color(1.0, 0.9, 0.35))
	label.text = "%s 使用技能\n%s" % [who, nm]
	label.position = Vector2(0, 260)
	label.size = Vector2(1280, 140)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(label)
	label.modulate.a = 0.0
	label.scale = Vector2(0.8, 0.8)
	label.pivot_offset = Vector2(640, 70)
	var tw := create_tween()
	tw.tween_property(label, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.1)
	tw.tween_property(label, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		if root != null and is_instance_valid(root):
			root.queue_free()
		if _announce_root == root:
			_announce_root = null
	)
	_announce_tween = tw


func _activate_skill(perk_id: String, side: int) -> void:
	_record_skill(side, perk_id)
	# 目标型技能:进入选目标阶段,不立即提醒(选完目标执行时才提醒,见各 _handle_*_target)
	var is_targeting_now: bool = _is_targeting_skill(perk_id)
	if not is_targeting_now:
		# 全局释放提醒(屏幕中央)
		_show_skill_announce(perk_id, side)
	match perk_id:
		"nvjisi", "nvjisi2":
			_skill_priestess(perk_id, side)
		"yuzhe", "yuzhe2":
			_skill_fool(perk_id, side)
		"jiezhi", "jiezhi2":
			_skill_temperance(perk_id, side)
		"huanghou", "huanghou2":
			_skill_queen(perk_id, side)
		"mingyun", "mingyun2":
			_skill_wheel(perk_id, side)
		"yinzhe2":
			_skill_hermit(perk_id, side)
		"zhengyi2":
			_skill_justice2(side)
		"siwang2":
			_skill_death2(side)
		"lianren2":
			_skill_lianren2(side)
		"moshushi", "moshushi2", "huangdi", "huangdi2", "siwang", "yinzhe":
			_start_targeting(perk_id, side)
		"diaodiao":
			# 正位:切换操控模式(己方↔非己方),跳过本回合
			control_foreign[side] = not control_foreign[side]
			_apply_skill_cd(perk_id, side)
			status_label.text = "倒吊人:切换为操控%s棋子" % ("非己方" if control_foreign[side] else "己方")
			_consume_turn_after_skill()
		"diaodiao2":
			# 逆位:跳过本回合,下回合起获得所有对方棋子控制权三回合
			controlled_all_turns = 3
			controlled_all_owner = side
			_apply_skill_cd(perk_id, side)
			status_label.text = "倒吊人:跳过本回合,下回合起控制所有对方棋子三回合"
			_consume_turn_after_skill()
		"xingxing2":
			# 星星逆位:获得 2 蓄势(每蓄势可免费移动一个兵),跳过本回合
			star2_charge[side] += 2
			_apply_skill_cd(perk_id, side)
			status_label.text = "星星:获得 2 蓄势(可免费移动 2 个兵),跳过本回合"
			_consume_turn_after_skill()
		_:
			status_label.text = "[%s] 该主动技能暂未实现" % perks_data[perk_id]["name"]
	# 同步技能执行完:补记棋盘快照(异步 targeting 技能在 _done_targeting 补)
	_snapshot_last_board()
	# 联机主机:本地释放技能后广播屏幕中央提醒(客户端执行时 _apply_net_skill 里已广播)
	# 目标型技能不在此广播:选完目标执行时才广播(见各 _handle_*_target),避免提前/重复提醒
	if net_role == "host" and Global.from_lobby and not _is_targeting_skill(perk_id):
		notify_skill_used.rpc(perk_id, side)


# ==================== 主动技能效果 ====================

func _skill_priestess(perk_id: String, side: int) -> void:
	if perk_id == "nvjisi2":
		# 进阶:底线生成随机棋子(去掉兵和士)
		var row := 9 if side == R.Side.RED else 0
		var slots: Array[Vector2i] = []
		for c in R.COLS:
			if board[row][c] == null:
				slots.append(Vector2i(c, row))
		if slots.is_empty():
			status_label.text = "底线已满,无法生成"
			return
		var pos: Vector2i = slots.pick_random()
		board[pos.y][pos.x] = R.make_piece(side, _random_piece_type(true))
		status_label.text = "女祭司:底线生成一个随机棋子(兵士除外)"
	else:
		# 普通:所有兵前进一格 + 补全兵线
		var fwd := R.pawn_fwd(side)
		var pawns: Array[Vector2i] = []
		for r in R.ROWS:
			for c in R.COLS:
				var p = board[r][c]
				if p != null and p["side"] == side and p["type"] == R.Type.PAWN:
					pawns.append(Vector2i(c, r))
		for pos in pawns:
			var tgt: Vector2i = pos + fwd
			if R.in_board(tgt) and board[tgt.y][tgt.x] == null:
				board[tgt.y][tgt.x] = board[pos.y][pos.x]
				board[pos.y][pos.x] = null
		var row := 6 if side == R.Side.RED else 3
		for c in R.COLS:
			if board[row][c] == null:
				board[row][c] = R.make_piece(side, R.Type.PAWN)
		status_label.text = "女祭司:所有兵前进一格,补全兵线"
	_apply_skill_cd(perk_id, side)
	queue_redraw()
	_consume_turn_after_skill()


func _skill_fool(perk_id: String, side: int) -> void:
	if perk_id == "yuzhe2":
		_fool_restore(side)
	else:
		_fool_shuffle(side)
	_apply_skill_cd(perk_id, side)
	_clear_selection()
	_refresh_move_log()
	queue_redraw()
	_consume_turn_after_skill()


# 愚者(普通):打乱棋子位置,每子 75% 概率不动;帅将士不动
func _fool_shuffle(side: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var positions: Array[Vector2i] = []
	var pieces: Array = []
	for r in R.ROWS:
		for c in R.COLS:
			var p = board[r][c]
			if p == null:
				continue
			if p["type"] == R.Type.KING or p["type"] == R.Type.ADVISOR:
				continue
			if rng.randf() < 0.75:
				continue  # 愚者:每子 75% 概率不动
			positions.append(Vector2i(c, r))
			pieces.append(p)
	pieces.shuffle()
	for i in positions.size():
		var pos: Vector2i = positions[i]
		board[pos.y][pos.x] = pieces[i]
	status_label.text = "愚者:棋子位置被打乱,跳过本回合!"


# 愚者(进阶):复原所有棋子位置(不复活被吃子)
func _fool_restore(side: int) -> void:
	var init: Array = initial_snapshot.get("board", [])
	if init.is_empty():
		status_label.text = "无开局快照,无法复原"
		return
	var pieces: Array = []
	for r in R.ROWS:
		for c in R.COLS:
			var p = board[r][c]
			if p != null:
				pieces.append({"piece": p, "type": p["type"], "side": p["side"]})
	for r in R.ROWS:
		for c in R.COLS:
			board[r][c] = null
	for item in pieces:
		var placed := false
		for r in R.ROWS:
			for c in R.COLS:
				var ip = init[r][c]
				if ip != null and ip["side"] == item["side"] and ip["type"] == item["type"] and board[r][c] == null:
					board[r][c] = item["piece"]
					placed = true
					break
			if placed:
				break
		if not placed:
			for r in R.ROWS:
				for c in R.COLS:
					if board[r][c] == null:
						board[r][c] = item["piece"]
						placed = true
						break
				if placed:
					break
	status_label.text = "愚者:所有棋子复原!"


func _skill_temperance(perk_id: String, side: int) -> void:
	if perk_id == "jiezhi2":
		# 进阶:本回合追加一次行动,跳过下回合(不占用移动)
		actions_left += 1
		skip_next_turn[side] = true
		_apply_skill_cd(perk_id, side)
		status_label.text = "节制:本回合追加行动,下回合跳过"
		queue_redraw()
		return
	# 普通:跳过本回合,下回合追加
	extra_turn[side] = true
	_apply_skill_cd(perk_id, side)
	status_label.text = "节制:跳过本回合,下回合追加行动"
	_consume_turn_after_skill()


func _skill_queen(perk_id: String, side: int) -> void:
	if perk_id == "huanghou2":
		# 进阶:所有棋子反制(被吃同归),持续到己方下回合开始
		if queen_charge[side] <= 0:
			status_label.text = "[皇后] 充能中:己方每被吃 1 子充能 1 点"
			return
		queen_charge[side] -= 1
		counter_side = side
		_apply_skill_cd(perk_id, side)
		status_label.text = "皇后:所有棋子获得反制(被吃同归于尽)"
		queue_redraw()
		_consume_turn_after_skill()
		return
	# 普通:所有棋子无敌,消耗被吃充能
	if queen_charge[side] <= 0:
		status_label.text = "[皇后] 充能中:己方每被吃 1 子充能 1 点"
		return
	queen_charge[side] -= 1
	invincible_side = side
	invincible_side_turns = 2
	status_label.text = "皇后:己方所有棋子无敌(持续2回合)"
	queue_redraw()
	_consume_turn_after_skill()


# 恋人(逆位):被吃充能(需求 2),使用后己方其他技能全部完成冷却/充能
func _skill_lianren2(side: int) -> void:
	if lianren2_charge[side] < 2:
		status_label.text = "[恋人] 充能中:己方每被吃 1 子充能 1 点(需 2 点)"
		return
	lianren2_charge[side] -= 2
	# 己方其他主动技能冷却清零
	for id in skill_cd[side].keys():
		skill_cd[side][id] = 0
	# 皇后/死亡充能补满(到各自上限;逆位力量可累计至 3 倍)
	var qcap := 3 if perks_of(side).has("liliang2") else 1
	if perks_of(side).has("huanghou") or perks_of(side).has("huanghou2"):
		queen_charge[side] = qcap
	var scap := 9 if perks_of(side).has("liliang2") else 3
	if perks_of(side).has("siwang") or perks_of(side).has("siwang2"):
		siwang_charge[side] = scap
	status_label.text = "恋人:己方其他技能全部完成冷却/充能"
	_refresh_perk_panels()
	queue_redraw()
	_consume_turn_after_skill()


func _skill_wheel(perk_id: String, side: int) -> void:
	if perk_id == "mingyun2":
		# 进阶:随机两子协同(移动不消耗步数),不跳过本回合
		var own: Array[Vector2i] = []
		for r in R.ROWS:
			for c in R.COLS:
				var p = board[r][c]
				if p != null and p["side"] == side and p["type"] != R.Type.KING:
					own.append(Vector2i(c, r))
		if own.size() < 2:
			status_label.text = "己方棋子不足,无法协同"
			return
		own.shuffle()
		sync_pieces = [own[0], own[1]]
		_apply_skill_cd(perk_id, side)
		status_label.text = "命运之轮:随机两子协同(移动不消耗步数)"
		queue_redraw()
		_update_ui()
		return
	# 普通:本回合可额外移动一次(不能连续动同一子),释放不消耗本回合
	actions_left += 1
	_apply_skill_cd(perk_id, side)
	status_label.text = "命运之轮:本回合可额外移动一次"
	queue_redraw()
	_update_ui()


func _skill_hermit(perk_id: String, side: int) -> void:
	if perk_id == "yinzhe2":
		# 进阶:己方所有子隐身(每回合每子 10% 概率破隐,移动后立刻破隐)
		# 标记用 side+100 区分"逆位持久隐身"(不受一回合清除影响)
		for r in R.ROWS:
			for c in R.COLS:
				var p = board[r][c]
				if p != null and p["side"] == side and p["type"] != R.Type.KING:
					hidden_pieces[Vector2i(c, r)] = side + 100
		_apply_skill_cd(perk_id, side)
		status_label.text = "隐者:己方所有子隐身(每回合10%概率破隐,移动即破隐)"
		queue_redraw()
		_consume_turn_after_skill()
		return
	# 普通:下回合移动的子隐身(释放不消耗本回合,还能走子)
	hermit_pending = true
	_apply_skill_cd(perk_id, side)
	status_label.text = "隐者:下回合移动的子隐身一回合"
	queue_redraw()


# 正义(进阶):炮隔子数在隔一子/隔两子间切换
func _skill_justice2(side: int) -> void:
	if perks_of(side).has("_cannon_2"):
		perks_of(side).erase("_cannon_2")
		status_label.text = "正义:炮恢复隔一子吃"
	else:
		perks_of(side)["_cannon_2"] = true
		status_label.text = "正义:炮变为隔两子吃"
	_apply_skill_cd("zhengyi2", side)
	queue_redraw()
	_consume_turn_after_skill()


# 死亡(进阶):随机摧毁敌我各一子(将帅除外),己方 50% 免疫
func _skill_death2(side: int) -> void:
	if siwang_charge[side] <= 0:
		status_label.text = "[死亡] 充能中:己方每被吃 1 子充能 1 点"
		return
	siwang_charge[side] -= 1
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var own: Array[Vector2i] = []
	var enemy: Array[Vector2i] = []
	for r in R.ROWS:
		for c in R.COLS:
			var q = board[r][c]
			if q == null or q["type"] == R.Type.KING:
				continue
			var v := Vector2i(c, r)
			if q["side"] == side:
				own.append(v)
			else:
				enemy.append(v)
	if not own.is_empty():
		var o: Vector2i = own.pick_random()
		if rng.randf() >= 0.5:
			board[o.y][o.x] = null
	if not enemy.is_empty():
		var e: Vector2i = enemy.pick_random()
		board[e.y][e.x] = null
	_apply_skill_cd("siwang2", side)
	status_label.text = "死亡:随机摧毁敌我各一子"
	_refresh_move_log()
	queue_redraw()
	_consume_turn_after_skill()


# ==================== 目标选择(主动技能) ====================

func _start_targeting(perk_id: String, side: int) -> void:
	targeting = {"perk": perk_id, "side": side, "stage": 1, "data": {}}
	_clear_selection()
	match perk_id:
		"moshushi", "moshushi2":
			status_label.text = "选择要交换的第一个棋子"
		"huangdi", "huangdi2":
			status_label.text = "选择己方一枚棋子"
		"zhanche", "zhanche2":
			status_label.text = "选择己方的车"
		"siwang":
			status_label.text = "选择己方一枚棋子(摧毁敌我同类型)"
		"diaodiao", "diaodiao2":
			status_label.text = "选择要控制的对方棋子"
		"yinzhe":
			status_label.text = "选择第一枚要隐身的己方棋子"
		_:
			status_label.text = "选择目标:请点击棋盘上的棋子"


func _handle_target_click(pos: Vector2i) -> void:
	var perk_id: String = targeting["perk"]
	var side: int = targeting["side"]
	match perk_id:
		"moshushi", "moshushi2":
			_handle_swap_target(pos, side, perk_id)
		"huangdi":
			_handle_king_guard(pos, side)
		"huangdi2":
			_handle_king_counter(pos, side)
		"zhanche", "zhanche2":
			_handle_chariot_target(pos, side, perk_id)
		"siwang":
			_handle_death_target(pos, side)
		"diaodiao", "diaodiao2":
			_handle_puppet_target(pos, side, perk_id)
		"yinzhe":
			_handle_hermit_target(pos, side)
		_:
			_done_targeting()
	queue_redraw()


# 魔术师:交换两子位置(普通=己方,进阶=对方)
func _handle_swap_target(pos: Vector2i, side: int, perk_id: String) -> void:
	var need_side: int = side if perk_id == "moshushi" else 1 - side
	var p = board[pos.y][pos.x]
	if p == null or p["side"] != need_side:
		status_label.text = "请选择%s的棋子" % ("己方" if perk_id == "moshushi" else "对方")
		return
	# 逆位(交换对方棋子):敌方将/帅不可被交换
	if perk_id == "moshushi2" and p["type"] == R.Type.KING:
		status_label.text = "逆位魔术师:不能交换对方将/帅"
		return
	if targeting["stage"] == 1:
		targeting["data"]["a"] = pos
		targeting["stage"] = 2
		status_label.text = "再选择要交换的第二个棋子"
		return
	var a: Vector2i = targeting["data"]["a"]
	if pos == a:
		status_label.text = "不能与自身交换"
		return
	if net_role == "client":
		_done_targeting()
		request_skill.rpc_id(1, perk_id, {"a": [a.x, a.y], "b": [pos.x, pos.y]})
		status_label.text = "魔术师:技能已发送,等待同步"
		return
	var pa = board[a.y][a.x]
	board[a.y][a.x] = p
	board[pos.y][pos.x] = pa
	_done_targeting()
	_apply_skill_cd(perk_id, side)
	status_label.text = "魔术师:两子位置已交换"
	_show_skill_announce(perk_id, side)
	_refresh_move_log()
	if net_role == "host":
		notify_skill_used.rpc(perk_id, side)
		_consume_turn_after_skill()
		_broadcast_state()


# 皇帝:指定己方一子本回合无敌
func _handle_king_guard(pos: Vector2i, side: int) -> void:
	var p = board[pos.y][pos.x]
	if p == null or p["side"] != side:
		status_label.text = "请选择己方棋子"
		return
	if net_role == "client":
		_done_targeting()
		request_skill.rpc_id(1, "huangdi", {"pos": [pos.x, pos.y]})
		status_label.text = "皇帝:技能已发送,等待同步"
		return
	invincible_piece = pos
	invincible_piece_side = side
	invincible_piece_turns = 3
	_apply_skill_cd("huangdi", side)
	_done_targeting()
	status_label.text = "皇帝:该子无敌(持续3回合)"
	_show_skill_announce("huangdi", side)
	queue_redraw()
	if net_role == "host":
		notify_skill_used.rpc("huangdi", side)
		_consume_turn_after_skill()
		_broadcast_state()


# 皇帝(进阶):指定己方一子反制(被吃同归)
func _handle_king_counter(pos: Vector2i, side: int) -> void:
	var p = board[pos.y][pos.x]
	if p == null or p["side"] != side:
		status_label.text = "请选择己方棋子"
		return
	if net_role == "client":
		_done_targeting()
		request_skill.rpc_id(1, "huangdi2", {"pos": [pos.x, pos.y]})
		status_label.text = "皇帝:技能已发送,等待同步"
		return
	suicide_mark = {"pos": pos, "side": side}
	_apply_skill_cd("huangdi2", side)
	_done_targeting()
	status_label.text = "皇帝:标记棋子,被吃时同归于尽"
	_show_skill_announce("huangdi2", side)
	queue_redraw()
	if net_role == "host":
		notify_skill_used.rpc("huangdi2", side)
		_consume_turn_after_skill()
		_broadcast_state()


# 死亡:选己方一子,摧毁敌我各一枚同类型子(消耗被吃充能)
func _handle_death_target(pos: Vector2i, side: int) -> void:
	var p = board[pos.y][pos.x]
	if p == null or p["side"] != side:
		status_label.text = "请选择己方棋子"
		return
	if siwang_charge[side] <= 0:
		status_label.text = "[死亡] 充能中:己方每被吃 1 子充能 1 点"
		return
	if net_role == "client":
		_done_targeting()
		request_skill.rpc_id(1, "siwang", {"pos": [pos.x, pos.y]})
		status_label.text = "死亡:技能已发送,等待同步"
		return
	siwang_charge[side] -= 1
	_destroy_same_type(pos, side)
	_done_targeting()
	_show_skill_announce("siwang", side)
	if net_role == "host":
		notify_skill_used.rpc("siwang", side)
		_consume_turn_after_skill()
		_broadcast_state()


# 倒吊人:获得对方一子控制权(普通=一回合,进阶=三回合且不能吃子)
func _handle_puppet_target(pos: Vector2i, side: int, perk_id: String) -> void:
	var p = board[pos.y][pos.x]
	if p == null or p["side"] == side:
		status_label.text = "请选择对方的棋子"
		return
	if net_role == "client":
		_done_targeting()
		request_skill.rpc_id(1, perk_id, {"pos": [pos.x, pos.y]})
		status_label.text = "倒吊人:技能已发送,等待同步"
		return
	controlled_piece = {"pos": pos, "owner": side}
	controlled_turns = 3 if perk_id == "diaodiao2" else 1
	_apply_skill_cd(perk_id, side)
	_done_targeting()
	if perk_id == "diaodiao2":
		status_label.text = "倒吊人:获得对方棋子控制权三回合(不能吃子)"
	else:
		status_label.text = "倒吊人:已获得对方棋子控制权"
	_show_skill_announce(perk_id, side)
	queue_redraw()
	if net_role == "host":
		notify_skill_used.rpc(perk_id, side)
		_consume_turn_after_skill()
		_broadcast_state()


# 隐者(普通):指定两子隐身两回合(分两步选己方两子)
func _handle_hermit_target(pos: Vector2i, side: int) -> void:
	var p = board[pos.y][pos.x]
	if p == null or p["side"] != side:
		status_label.text = "请选择己方棋子"
		return
	if targeting["stage"] == 1:
		targeting["data"]["a"] = pos
		targeting["stage"] = 2
		status_label.text = "再选择第二枚要隐身的己方棋子"
		return
	var a: Vector2i = targeting["data"]["a"]
	if pos == a:
		status_label.text = "不能与自身相同"
		return
	if net_role == "client":
		_done_targeting()
		request_skill.rpc_id(1, "yinzhe", {"a": [a.x, a.y], "b": [pos.x, pos.y]})
		status_label.text = "隐者:技能已发送,等待同步"
		return
	_apply_hermit_target(a, pos, side)
	_done_targeting()
	_apply_skill_cd("yinzhe", side)
	status_label.text = "隐者:指定两子隐身两回合"
	_show_skill_announce("yinzhe", side)
	_refresh_move_log()
	queue_redraw()
	if net_role == "host":
		notify_skill_used.rpc("yinzhe", side)
		_consume_turn_after_skill()
		_broadcast_state()


# 隐者(普通):两子标记为隐身 2 回合(side+200 = 指定两子隐身,剩余回合存 hidden_turns)
func _apply_hermit_target(a: Vector2i, b: Vector2i, side: int) -> void:
	hidden_pieces[a] = side + 200
	hidden_turns[a] = 2
	hidden_pieces[b] = side + 200
	hidden_turns[b] = 2


func _handle_chariot_target(pos: Vector2i, side: int, perk_id: String) -> void:
	var stage: int = targeting["stage"]
	var p = board[pos.y][pos.x]
	if stage == 1:
		if p == null or p["side"] != side or p["type"] != R.Type.ROOK:
			status_label.text = "请选择己方的车"
			return
		targeting["stage"] = 2
		targeting["data"]["rook"] = pos
		status_label.text = "再选择车相邻的一枚棋子(正位:己方;逆位:含敌方)"
	elif stage == 2:
		var rook: Vector2i = targeting["data"]["rook"]
		var adj: bool = absi(pos.x - rook.x) + absi(pos.y - rook.y) == 1
		if perk_id == "zhanche2" and adj:
			adj = absi(pos.x - rook.x) != 1 or absi(pos.y - rook.y) != 1  # 进阶:不含对角相邻
		if p == null or not adj:
			status_label.text = "请选择与车相邻(不含对角)的棋子" if perk_id == "zhanche2" else "请选择与车相邻的棋子"
			return
		if perk_id == "zhanche" and p["side"] != side:
			status_label.text = "请选择与车相邻的己方棋子"
			return
		targeting["stage"] = 3
		targeting["data"]["piece"] = pos
		# 逆位:车移动到相邻子可落位;正位:相邻子移动到车可落位
		if perk_id == "zhanche2":
			targeting["data"]["landings"] = R.legal_moves(board, pos, perks_red, perks_black)
			status_label.text = "点击可落位,将车移至此处(通过相邻子移动车)"
		else:
			targeting["data"]["landings"] = R.legal_moves(board, rook, perks_red, perks_black)
			status_label.text = "点击车的可落位,将该子移至此处"
	elif stage == 3:
		var landings: Array = targeting["data"]["landings"]
		if not pos in landings:
			status_label.text = "请点击车的可落位点"
			return
		var from: Vector2i = targeting["data"]["piece"]
		if net_role == "client":
			_done_targeting()
			request_skill.rpc_id(1, perk_id, {"piece": [from.x, from.y], "landing": [pos.x, pos.y]})
			status_label.text = "战车:技能已发送,等待同步"
			return
		var rook_pos: Vector2i = targeting["data"]["rook"]
		if perk_id == "zhanche2":
			# 逆位:移动车到相邻子的可落位
			var rook_piece = board[rook_pos.y][rook_pos.x]
			board[rook_pos.y][rook_pos.x] = null
			board[pos.y][pos.x] = rook_piece
			status_label.text = "战车:车已移至相邻子的可落位"
		else:
			var piece = board[from.y][from.x]
			board[from.y][from.x] = null
			board[pos.y][pos.x] = piece
			status_label.text = "战车:棋子已移至车可落位"
		_done_targeting()
		_apply_skill_cd(perk_id, side)
		_show_skill_announce(perk_id, side)
		_refresh_move_log()
		if net_role == "host":
			notify_skill_used.rpc(perk_id, side)
			_consume_turn_after_skill()
			_broadcast_state()


func _destroy_same_type(pos: Vector2i, side: int) -> void:
	# 死亡:摧毁敌我各一枚指定的同类型子
	var p = board[pos.y][pos.x]
	var t: int = p["type"]
	var enemy := 1 - side
	var enemy_pos := Vector2i(-1, -1)
	for r in R.ROWS:
		for c in R.COLS:
			var q = board[r][c]
			if q != null and q["side"] == enemy and q["type"] == t:
				enemy_pos = Vector2i(c, r)
				break
		if enemy_pos.x >= 0:
			break
	board[pos.y][pos.x] = null
	if enemy_pos.x >= 0:
		board[enemy_pos.y][enemy_pos.x] = null
	status_label.text = "死亡:敌我各一枚同类型子被摧毁"
	_refresh_move_log()


func _done_targeting() -> void:
	targeting = {}
	_clear_selection()
	# targeting 技能执行完:补记棋盘快照(供复盘/悔棋还原技能造成的棋盘变化)
	_snapshot_last_board()



# ==================== 交互 ====================

func _unhandled_input(event: InputEvent) -> void:
	if four_mode:
		_handle_input4(event)
		return
	if replay_mode:
		return
	if phase != Phase.PLAY:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _is_human_turn():
			return
		# 用事件自带坐标(比 get_global_mouse_position 更可靠,窗口缩放/黑边时也准确)
		var gp: Vector2 = event.position
		# 四舍五入取最近的交点;黑方客户端视角 180° 翻转
		var c := roundi((gp.x - ORIGIN.x) / CELL)
		var r := roundi((gp.y - ORIGIN.y) / CELL)
		if flip_board:
			c = (R.COLS - 1) - c
			r = (R.ROWS - 1) - r
		var pos := Vector2i(c, r)
		if R.in_board(pos):
			if not targeting.is_empty():
				_handle_target_click(pos)
			else:
				_handle_click(pos)


func _is_human_turn() -> bool:
	if net_role == "host":
		return turn == R.Side.RED
	if net_role == "client":
		return turn == R.Side.BLACK
	return Global.game_mode != "ai" or turn == R.Side.RED


func _handle_click(pos: Vector2i) -> void:
	var p = board[pos.y][pos.x]
	var is_controlled: bool = not controlled_piece.is_empty() and pos == controlled_piece.get("pos", Vector2i(-1, -1)) and controlled_piece.get("owner", -1) == turn
	# 倒吊人正位:切换操控模式——只能操控非己方棋子
	var can_operate: bool = p != null and (p["side"] == turn or is_controlled or (control_foreign[turn] and p["side"] != turn))
	if selected.x < 0:
		if can_operate:
			_select(pos)
		return
	if pos == selected:
		_clear_selection()
		return
	# 免费移动优先:星星(兵)/月亮逆位(象)的落点即使也在普通走法里,也应免费执行
	if pos in free_retreat_targets:
		_try_perform(selected, pos, "free_retreat")
		return
	if pos in free_elephant_targets:
		_try_perform(selected, pos, "free_elephant")
		return
	if pos in moves_cache:
		_try_perform(selected, pos, "move")
		return
	if can_operate:
		_select(pos)
	else:
		_clear_selection()


func _clear_selection() -> void:
	selected = Vector2i(-1, -1)
	moves_cache = []
	free_retreat_targets = []
	free_elephant_targets = []
	queue_redraw()


# 隐身子在当前视角是否可见:己方的可见(半透明+标记),对方的完全隐藏
func _is_visible_hidden(side: int) -> bool:
	if net_role == "host":
		return side == R.Side.RED
	if net_role == "client":
		return side == R.Side.BLACK
	return true  # 本地模式(人机/双人)同屏,双方都可见


# 四人:联机时只有本机视角能看到自己的隐身棋子;本地四人同屏全可见
func _is_visible_hidden4(side: int) -> bool:
	if net_role == "local" or my_side4 < 0:
		return true
	return side == my_side4


func _select(pos: Vector2i) -> void:
	# 额外行动(命运之轮):本回合已移动过的棋子不能再次移动
	if first_moved.x >= 0 and pos == first_moved:
		return
	# 协同棋子:本回合已免费移动过一次的不能再移动(防无限移动)
	if pos in _sync_moved:
		return
	selected = pos
	moves_cache = R.legal_moves(board, pos, perks_red, perks_black)
	# 隐者:隐身的子不能吃子(只能移动)
	var self_hidden: bool = hidden_pieces.has(pos)
	# 倒吊人:控制权棋子移动时不能吃子(进阶)
	var controlled_move: bool = controlled_turns > 0 and not controlled_piece.is_empty() and pos == controlled_piece.get("pos", Vector2i(-1, -1))
	# 倒吊人正位:切换操控模式——选中的是非己方棋子
	var foreign_sel: bool = control_foreign[turn] and board[pos.y][pos.x] != null and board[pos.y][pos.x]["side"] != turn
	# 过滤受保护目标:皇后无敌 / 皇帝指定无敌 / 教皇象无敌 / 恶魔禁同类型连续吃
	if not moves_cache.is_empty():
		var filtered: Array[Vector2i] = []
		for m in moves_cache:
			if board[m.y][m.x] != null:
				var ts: int = board[m.y][m.x]["side"]
				if invincible_side == ts or m == invincible_piece:
					continue
				if pope_guarded.has(m):
					continue  # 教皇:象路径阻挡的己方棋子无敌
				if perks_of(ts).has("emo") and last_eat["side"] == turn and last_eat["type"] == board[pos.y][pos.x]["type"]:
					continue  # 恶魔:敌方不能用同类型子连续吃
				if self_hidden:
					continue  # 隐身的子不能吃子
				if controlled_move:
					continue  # 控制权(进阶):不能吃子
				# 正位切换模式:操控的非己方棋子不能吃操控方自己的王
				if foreign_sel and ts == turn and board[m.y][m.x]["type"] == R.Type.KING:
					continue
			filtered.append(m)
		moves_cache = filtered
	free_retreat_targets = []
	free_elephant_targets = []
	var p = board[pos.y][pos.x]
	# 月亮逆位:象的落位中空格部分免费(蓝色,不消耗步数)
	if p["type"] == R.Type.ELEPHANT and perks_of(turn).has("yueliang2"):
		for m in R.legal_moves(board, pos, perks_red, perks_black):
			if board[m.y][m.x] == null:
				free_elephant_targets.append(m)
	# 星星:兵免费移动(蓝色,仅空格,任意方向一格)
	# 正位:每回合一次;逆位:消耗蓄势(每蓄势一次,允许连续移动同一兵)
	var star_free: bool = false
	if p["type"] == R.Type.PAWN:
		if perks_of(turn).has("xingxing") and not free_retreat_used:
			star_free = true
		elif perks_of(turn).has("xingxing2") and star2_charge[turn] > 0:
			star_free = true
	if star_free:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var free_mv: Vector2i = pos + d
			if R.in_board(free_mv) and board[free_mv.y][free_mv.x] == null:
				free_retreat_targets.append(free_mv)
	# 战车(被动·整局):与车相邻的棋子可落至车的可落位;选中车时可落至相邻子(含敌方)的可落位
	var chariot_extra: Array[Vector2i] = _chariot_boost_moves(pos, turn)
	for m in chariot_extra:
		if m in moves_cache:
			continue
		# 与主循环一致的受保护目标过滤(无敌/教皇/恶魔禁吃/隐身不能吃)
		if board[m.y][m.x] != null:
			var ts3: int = board[m.y][m.x]["side"]
			if invincible_side == ts3 or m == invincible_piece:
				continue
			if pope_guarded.has(m):
				continue
			if perks_of(ts3).has("emo") and last_eat["side"] == turn and last_eat["type"] == board[pos.y][pos.x]["type"]:
				continue
			if self_hidden:
				continue
			if controlled_move:
				continue
		moves_cache.append(m)
	queue_redraw()


# 战车(被动):返回选中 pos 的战车强化落位(整局生效,无次数限制)
# 正位:选中的是己方棋子且与己方车相邻 → 车的可落位并入
# 逆位:选中的是己方车 → 与其相邻子(含敌方)的可落位并入
func _chariot_boost_moves(pos: Vector2i, side: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var p = board[pos.y][pos.x]
	if p == null or p["side"] != side:
		return out
	var perks := perks_of(side)
	if p["type"] == R.Type.ROOK and perks.has("zhanche2"):
		# 逆位:车的可落位 = 相邻子(含敌方)的可落位
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var np: Vector2i = pos + d
			if not R.in_board(np):
				continue
			var q = board[np.y][np.x]
			if q == null:
				continue
			for m in R.legal_moves(board, np, perks_red, perks_black):
				if not m in out:
					out.append(m)
	elif perks.has("zhanche"):
		# 正位:与己方车相邻 → 该车可落位并入
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var np: Vector2i = pos + d
			if not R.in_board(np):
				continue
			var q = board[np.y][np.x]
			if q != null and q["side"] == side and q["type"] == R.Type.ROOK:
				for m in R.legal_moves(board, np, perks_red, perks_black):
					if not m in out:
						out.append(m)
	return out


# ==================== AI ====================

func _maybe_ai() -> void:
	if net_role != "local" or Global.game_mode != "ai" or turn != R.Side.BLACK or phase != Phase.PLAY or ai_busy:
		return
	ai_busy = true
	await get_tree().create_timer(0.4).timeout
	ai_busy = false
	if phase != Phase.PLAY or turn != R.Side.BLACK:
		return
	if not R.has_legal_move(board, turn, perks_red, perks_black):
		_win(1 - turn)
		return
	var mv := _choose_ai_move()
	if mv.is_empty():
		_win(1 - turn)
	else:
		_perform_move(mv["from"], mv["to"])


# AI 选走法:自动避开会被规则拦截的吃子(隐身子/教皇保护/无敌/恶魔禁吃)
func _choose_ai_move() -> Dictionary:
	var best := AI.choose_move(board, turn, perks_red, perks_black)
	if best.is_empty():
		return {}
	var from: Vector2i = best["from"]
	var to: Vector2i = best["to"]
	if _ai_move_blocked(from, to):
		# 首选:该子其它不被拦截的走法
		for m in R.legal_moves(board, from, perks_red, perks_black):
			if not _ai_move_blocked(from, m):
				return {"from": from, "to": m}
		# 次选:其它棋子的任意不被拦截走法
		for r in R.ROWS:
			for c in R.COLS:
				var p = board[r][c]
				if p == null or p["side"] != turn:
					continue
				var f2 := Vector2i(c, r)
				for m2 in R.legal_moves(board, f2, perks_red, perks_black):
					if not _ai_move_blocked(f2, m2):
						return {"from": f2, "to": m2}
		return {}
	return best


# AI 走法是否会被规则拦截(与 _validate_move 的拦截一致)
func _ai_move_blocked(from: Vector2i, to: Vector2i) -> bool:
	var mover = board[from.y][from.x]
	if mover == null:
		return true
	var captured = board[to.y][to.x]
	if captured == null:
		return false
	# 隐身的子不能吃子
	if hidden_pieces.has(from):
		return true
	var ts: int = captured["side"]
	# 无敌/教皇保护:不可吃
	if to == invincible_piece or invincible_side == ts:
		return true
	if pope_guarded.has(to):
		return true
	# 恶魔:敌方同类型子被禁吃
	if perks_of(ts).has("emo") and last_eat["side"] == turn and last_eat["type"] == mover["type"]:
		return true
	# 恶魔逆位:被吃方 2 回合内只能被该类型攻击
	if perks_of(ts).has("emo2") and emo2_turns[ts] > 0 and mover["type"] != emo2_type[ts]:
		return true
	return false


# ==================== 渲染 ====================

func _draw() -> void:
	if four_mode:
		_draw_board4()
		_draw_pieces4()
		_draw_overlay4()
		_draw_particles4()
		return
	_draw_board()
	_draw_pieces(_display_board())
	_draw_overlay(_display_board())
	_draw_debris()


func _display_board() -> Array:
	return replay_board if replay_mode else board


func _draw_board() -> void:
	var line := Color(0.25, 0.2, 0.15)
	draw_rect(Rect2(ORIGIN - Vector2(6, 6), Vector2(BOARD_W + 12, BOARD_H + 12)), Color(0.86, 0.78, 0.62))
	# 竖线(河界处断开:横线 4 与 5 之间)
	for c in R.COLS:
		var x := ORIGIN.x + c * CELL
		if c == 0 or c == 8:
			draw_line(Vector2(x, ORIGIN.y), Vector2(x, ORIGIN.y + BOARD_H), line, 2.0)
		else:
			draw_line(Vector2(x, ORIGIN.y), Vector2(x, ORIGIN.y + 4 * CELL), line, 1.0)
			draw_line(Vector2(x, ORIGIN.y + 5 * CELL), Vector2(x, ORIGIN.y + BOARD_H), line, 1.0)
	# 横线
	for r in R.ROWS:
		var y := ORIGIN.y + r * CELL
		draw_line(Vector2(ORIGIN.x, y), Vector2(ORIGIN.x + BOARD_W, y), line, 2.0 if r == 0 or r == 9 else 1.0)
	# 九宫斜线
	draw_line(_pos_px(Vector2i(3, 7)), _pos_px(Vector2i(5, 9)), line, 1.0)
	draw_line(_pos_px(Vector2i(5, 7)), _pos_px(Vector2i(3, 9)), line, 1.0)
	draw_line(_pos_px(Vector2i(3, 0)), _pos_px(Vector2i(5, 2)), line, 1.0)
	draw_line(_pos_px(Vector2i(5, 0)), _pos_px(Vector2i(3, 2)), line, 1.0)
	# 河界标注:左侧"楚河",右侧"汉界"(位于横线 4 与 5 之间的中心)
	_draw_text(ORIGIN + Vector2(BOARD_W * 0.25, 4.5 * CELL), "楚河", 30, Color(0.45, 0.35, 0.22))
	_draw_text(ORIGIN + Vector2(BOARD_W * 0.75, 4.5 * CELL), "汉界", 30, Color(0.45, 0.35, 0.22))


func _draw_pieces(db: Array) -> void:
	if db.is_empty():
		return
	# 动画中棋子的目标位置:绘制时跳过(由动画层绘制插值位置,与四人一致)
	var anim_targets := {}
	for a in _move_anims:
		anim_targets[a["to_px"]] = true
	for r in db.size():
		for c in db[r].size():
			var p = db[r][c]
			if p == null:
				continue
			var hpos := Vector2i(c, r)
			var is_hidden: bool = hidden_pieces.has(hpos)
			if is_hidden and not _is_visible_hidden(int(hidden_pieces[hpos]) % 100):
				continue  # 对方的隐身棋子:完全看不到,不绘制
			var center := _pos_px(hpos)
			if anim_targets.has(center):
				continue  # 动画棋子由动画层绘制
			# 隐者:己方隐身棋子半透明显示(可见"隐身中",且不能吃子)
			var alpha := 0.38 if is_hidden else 1.0
			# 像素化圆棋子:先画深色大圆当描边,再画小一号的底色圆盖住中心(深色只在边缘露出 1px)
			draw_texture_rect(_piece_texture(), Rect2(center - Vector2(24, 24), Vector2(48, 48)), false, Color(0.3, 0.22, 0.14, alpha))
			draw_texture_rect(_piece_texture(), Rect2(center - Vector2(23, 23), Vector2(46, 46)), false, Color(0.95, 0.9, 0.78, alpha))
			var sid: int = p["side"]
			var name: String = R.PIECE_NAMES[p["type"]] if (sid == 0 or sid == 2) else R.PIECE_NAMES_BLACK[p["type"]]
			var color: Color = _side_color(sid, alpha)
			# 文字向右、上偏移(像素风浮雕):右 3px、上 1px
			_draw_text(center + Vector2(3, -1), name, 27, color)
	# 动画层:棋子从起点平滑移动到终点
	for a in _move_anims:
		var prog: float = clampf(a["t"] / a["dur"], 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - prog, 3.0)  # ease-out 立方
		var fp: Vector2 = a["from_px"]
		var tp: Vector2 = a["to_px"]
		var pos: Vector2 = fp.lerp(tp, eased)
		_draw_piece_center(pos, a["piece"])


var _piece_tex: ImageTexture


# 双人棋子绘制(可指定中心像素,用于移动动画插值)
func _draw_piece_center(center: Vector2, p: Dictionary) -> void:
	var alpha := 1.0
	draw_texture_rect(_piece_texture(), Rect2(center - Vector2(24, 24), Vector2(48, 48)), false, Color(0.3, 0.22, 0.14, alpha))
	draw_texture_rect(_piece_texture(), Rect2(center - Vector2(23, 23), Vector2(46, 46)), false, Color(0.95, 0.9, 0.78, alpha))
	var sid: int = p["side"]
	var name: String = R.PIECE_NAMES[p["type"]] if (sid == 0 or sid == 2) else R.PIECE_NAMES_BLACK[p["type"]]
	var color: Color = _side_color(sid, alpha)
	_draw_text(center + Vector2(3, -1), name, 27, color)


# 棋子颜色:优先用大厅分配的 16 色;否则默认(0红 1黑 2绿 3蓝)
func _side_color(side: int, alpha: float = 1.0) -> Color:
	if Global.player_colors.has(side) and Global.player_colors[side] >= 0:
		var c: Color = Global.COLORS16[Global.player_colors[side]]
		return Color(c.r, c.g, c.b, alpha)
	match side:
		0: return Color(0.75, 0.15, 0.12, alpha)
		1: return Color(0.15, 0.13, 0.12, alpha)
		2: return Color(0.1, 0.6, 0.2, alpha)
		3: return Color(0.1, 0.35, 0.75, alpha)
	return Color(0.75, 0.15, 0.12, alpha)


func _piece_texture() -> ImageTexture:
	# 一次性生成硬边像素圆贴图(最近邻采样,边缘呈像素阶梯)
	if _piece_tex == null:
		var s := 48
		var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
		var c := Vector2(s / 2.0, s / 2.0)
		for y in s:
			for x in s:
				img.set_pixel(x, y, Color(1, 1, 1, 1) if Vector2(x, y).distance_to(c) <= 23.0 else Color(0, 0, 0, 0))
		_piece_tex = ImageTexture.create_from_image(img)
	return _piece_tex


func _draw_overlay(db: Array) -> void:
	if selected.x >= 0:
		draw_arc(_pos_px(selected), 25.0, 0, TAU, 32, Color(0.95, 0.8, 0.2), 3.0)
	# 协同棋子(命运之轮逆位):移动不消耗步数 = 免费移动,落点用蓝色
	var is_sync_sel: bool = selected.x >= 0 and selected in sync_pieces
	for m in moves_cache:
		# 落位指示器:对方看不到的隐身子视作空位(绿点),避免暴露隐身位置
		var target = db[m.y][m.x]
		var hidden_target: bool = target != null and hidden_pieces.has(m) and not _is_visible_hidden(int(hidden_pieces[m]) % 100)
		if is_sync_sel:
			draw_circle(_pos_px(m), 6.0, Color(0.3, 0.55, 0.95, 0.95))
		elif target != null and not hidden_target:
			draw_arc(_pos_px(m), 23.0, 0, TAU, 32, Color(0.85, 0.3, 0.25), 3.0)
		else:
			draw_circle(_pos_px(m), 6.0, Color(0.2, 0.7, 0.3, 0.9))
	# 免费退兵位(蓝色)
	for t in free_retreat_targets:
		draw_circle(_pos_px(t), 6.0, Color(0.3, 0.55, 0.95, 0.95))
	# 月亮逆位:象免费落位(蓝色)
	for t in free_elephant_targets:
		draw_circle(_pos_px(t), 6.0, Color(0.35, 0.6, 1.0, 0.95))
	# 皇帝:同归于尽标记(紫色框 = 反制,呼吸)
	var br := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
	var br_alpha := 0.7 + 0.3 * br
	if not suicide_mark.is_empty():
		var sp: Vector2i = suicide_mark["pos"]
		draw_arc(_pos_px(sp), 25.0 + br * 2.0, 0, TAU, 32, Color(0.6, 0.25, 0.85, br_alpha), 3.0)
	# 教皇:以象为中心5×5范围内除象以外的己方棋子获得无敌(金色描边,呼吸)
	for gpos in pope_guarded:
		draw_arc(_pos_px(gpos), 27.0 + br * 2.0, 0, TAU, 40, Color(0.95, 0.8, 0.2, br_alpha), 3.0)
	# 无敌状态:皇后全员无敌 / 皇帝指定无敌 → 金色描边(呼吸)
	if invincible_side >= 0 or invincible_piece.x >= 0:
		for r in db.size():
			for c in db[r].size():
				var q = db[r][c]
				if q == null:
					continue
				var qpos := Vector2i(c, r)
				if invincible_side == q["side"] or qpos == invincible_piece:
					draw_arc(_pos_px(qpos), 27.0 + br * 2.0, 0, TAU, 40, Color(0.95, 0.8, 0.2, br_alpha), 3.0)
	# 反制状态:皇后全员反制 / 教皇逆位象为中心5×5内的子反制 → 紫色描边(呼吸)
	var purple := Color(0.6, 0.25, 0.85, br_alpha)
	if counter_side >= 0:
		for r in db.size():
			for c in db[r].size():
				var q = db[r][c]
				if q == null:
					continue
				if q["side"] == counter_side:
					draw_arc(_pos_px(Vector2i(c, r)), 27.0 + br * 2.0, 0, TAU, 40, purple, 3.0)
	for cpos in pope_countered:
		draw_arc(_pos_px(cpos), 27.0 + br * 2.0, 0, TAU, 40, purple, 3.0)
	# 命运之轮(逆位):协同两子淡蓝色描边(呼吸)
	for spos in sync_pieces:
		draw_arc(_pos_px(spos), 29.0 + br * 2.0, 0, TAU, 40, Color(0.45, 0.8, 1.0, br_alpha), 3.0)
	# 隐者:隐身棋子只保留半透明(棋子本体绘制),不画"隐"字与描边,避免暴露隐身位置


func _pos_px(pos: Vector2i) -> Vector2:
	# 中国象棋:棋子落在棋盘线的交点上;黑方客户端视角 180° 翻转(上下+左右)
	var view_x := (R.COLS - 1) - pos.x if flip_board else pos.x
	var view_y := (R.ROWS - 1) - pos.y if flip_board else pos.y
	return ORIGIN + Vector2(view_x, view_y) * CELL


func _draw_text(center: Vector2, text: String, font_size: int, color: Color) -> void:
	var f := _font()
	var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	# 按字体 ascender/descender 精确垂直居中(baseline = center + (ascent - descent) / 2)
	var baseline_y := center.y + (f.get_ascent(font_size) - f.get_descent(font_size)) / 2.0
	draw_string(f, Vector2(center.x - ts.x / 2.0, baseline_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


# ==================== 四人模式(复制双人逻辑修改:走子规则复用 chess_rules) ====================

const CELL4 := 34
const ORIGIN4 := Vector2(351, 71)  # 17×17×34=578,居中
const GRID4 := 17
const CENTER4 := 4
const SIDE_ORDER4 := [1, 3, 0, 2]  # 黑→蓝→红→绿
const SIDE_NAMES4 := {0: "红方(下)", 1: "黑方(上)", 2: "绿方(左)", 3: "蓝方(右)"}

var _piece_tex4: ImageTexture
var _view_rot4 := 0   # 四人联机:本机视角旋转(0=红下,1=黑上180°,2=绿左90°CW,3=蓝右270°CW)


func _pos_px4(pos: Vector2i) -> Vector2:
	# 四人联机:按本机视角旋转后渲染,自己的半场在下方
	var v := pos
	if _view_rot4 == 1:
		v = Vector2i(GRID4 - 1 - pos.x, GRID4 - 1 - pos.y)   # 180°
	elif _view_rot4 == 2:
		v = Vector2i(pos.y, GRID4 - 1 - pos.x)               # 绿(左):270° 顺时针 → 下方
	elif _view_rot4 == 3:
		v = Vector2i(GRID4 - 1 - pos.y, pos.x)               # 蓝(右):90° 顺时针 → 下方
	# 与双人一致:棋子落在棋盘线交点上
	return ORIGIN4 + Vector2(v.x, v.y) * CELL4


# 显示坐标 → 逻辑坐标(输入反向映射)
func _unrot4(pos: Vector2i) -> Vector2i:
	if _view_rot4 == 1:
		return Vector2i(GRID4 - 1 - pos.x, GRID4 - 1 - pos.y)
	elif _view_rot4 == 2:
		return Vector2i(GRID4 - 1 - pos.y, pos.x)
	elif _view_rot4 == 3:
		return Vector2i(pos.y, GRID4 - 1 - pos.x)
	return pos


func _piece_texture4() -> ImageTexture:
	# 复制双人 _piece_texture:硬边像素圆(四人棋盘更小,圆 30px)
	if _piece_tex4 == null:
		var s := 30
		var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
		var c := Vector2(s / 2.0, s / 2.0)
		for y in s:
			for x in s:
				img.set_pixel(x, y, Color(1, 1, 1, 1) if Vector2(x, y).distance_to(c) <= 14.5 else Color(0, 0, 0, 0))
		_piece_tex4 = ImageTexture.create_from_image(img)
	return _piece_tex4


func _draw_board4() -> void:
	var wood := Color(0.86, 0.78, 0.62)
	var line := Color(0.4, 0.3, 0.2)
	# 间距数 = 格点数 - 1:半场横向 9 格点→8 间距,纵向 4 格点→3 间距;中心 9 格点→8 间距
	var c0 := ORIGIN4 + Vector2(CENTER4, CENTER4) * CELL4
	var csize := Vector2(8, 8) * CELL4
	var armW := 8 * CELL4  # 半场宽(9 格点 = 8 间距)
	var armH := 3 * CELL4  # 半场高(4 格点 = 3 间距)
	# 十字形木色底(中心 + 四臂);四角不画底
	draw_rect(Rect2(c0, csize), wood)
	draw_rect(Rect2(ORIGIN4 + Vector2(CENTER4, 0) * CELL4, Vector2(armW, armH)), wood)
	draw_rect(Rect2(ORIGIN4 + Vector2(CENTER4, 13) * CELL4, Vector2(armW, armH)), wood)
	draw_rect(Rect2(ORIGIN4 + Vector2(0, CENTER4) * CELL4, Vector2(armH, armW)), wood)
	draw_rect(Rect2(ORIGIN4 + Vector2(13, CENTER4) * CELL4, Vector2(armH, armW)), wood)
	# 中心正方形:十字线(9 条线覆盖 8 间距)+ 边框
	for i in 9:
		var y := c0.y + i * CELL4
		draw_line(Vector2(c0.x, y), Vector2(c0.x + csize.x, y), line, 1.0)
	for i in 9:
		var x := c0.x + i * CELL4
		draw_line(Vector2(x, c0.y), Vector2(x, c0.y + csize.y), line, 1.0)
	draw_rect(Rect2(c0, csize), line, false, 3.0)
	# 四个半场格子线(十字形,四角不画线)
	_draw_arm4(Rect2(ORIGIN4 + Vector2(CENTER4, 0) * CELL4, Vector2(armW, armH)), line)
	_draw_arm4(Rect2(ORIGIN4 + Vector2(CENTER4, 13) * CELL4, Vector2(armW, armH)), line)
	_draw_arm4(Rect2(ORIGIN4 + Vector2(0, CENTER4) * CELL4, Vector2(armH, armW)), line)
	_draw_arm4(Rect2(ORIGIN4 + Vector2(13, CENTER4) * CELL4, Vector2(armH, armW)), line)
	# 占领模式:中心 5 点用黑点标记(画在棋盘上、棋子下方)
	if Global.game_rules.get("win_mode", "classic") == "occupy":
		for spot in _occupy_spots4():
			draw_circle(_pos_px4(spot), 5.0, Color(0, 0, 0, 0.85))


func _draw_arm4(rect: Rect2, line: Color) -> void:
	var gw: int = int(rect.size.x / CELL4)
	var gh: int = int(rect.size.y / CELL4)
	for gy in gh:
		for gx in gw:
			var p := rect.position + Vector2(gx, gy) * CELL4
			draw_line(p, p + Vector2(CELL4, 0), line, 1.0)
			draw_line(p, p + Vector2(0, CELL4), line, 1.0)


func _draw_pieces4() -> void:
	# 复制双人 _draw_pieces:圆棋子 + 名字 + 4色,棋子落在交点
	if board.is_empty():
		return
	# 动画中棋子的目标位置:绘制时跳过(由动画层绘制插值位置)
	var anim_targets := {}
	for a in _move_anims:
		anim_targets[a["to_px"]] = true
	for r in board.size():
		for c in board[r].size():
			var p = board[r][c]
			if p == null:
				continue
			var hpos := Vector2i(c, r)
			var is_hidden: bool = hidden_pieces4.has(hpos)
			# 对方视角的隐身棋子:完全看不到,不绘制
			if is_hidden and not _is_visible_hidden4(int(hidden_pieces4[hpos]) % 100):
				continue
			var center := _pos_px4(hpos)
			if anim_targets.has(center):
				continue  # 动画棋子由动画层绘制
			# 己方隐身子:半透明显示(可见"隐身中",且不能吃子)
			var alpha := 0.38 if is_hidden else 1.0
			_draw_piece4(center, p, alpha)
	# 动画层:棋子从起点平滑移动到终点
	for a in _move_anims:
		var prog: float = clampf(a["t"] / a["dur"], 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - prog, 3.0)  # ease-out 立方
		var fp: Vector2 = a["from_px"]
		var tp: Vector2 = a["to_px"]
		var pos: Vector2 = fp.lerp(tp, eased)
		_draw_piece4(pos, a["piece"])


# 吃子特效:屏幕震动 + 被吃子粒子破碎消散
func _trigger_capture_effect4(captured: Dictionary, to: Vector2i) -> void:
	Global.play_sfx("kill", -4.0)
	_shake_time = 0.3
	_shake_strength = 9.0
	# 被吃子位置生成碎片(颜色 = 被吃方颜色)
	var center: Vector2 = _pos_px4(to)
	var col: Color = _side_color(captured["side"])
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 14:
		var ang := rng.randf() * TAU
		var spd := rng.randf_range(40.0, 140.0)
		_debris.append({
			"pos": center,
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"life": rng.randf_range(0.35, 0.6),
			"max": 0.6,
			"size": rng.randf_range(3.0, 6.0),
			"color": col,
		})
	queue_redraw()


# 绘制破碎粒子(小方块,生命衰减透明度)
func _draw_debris() -> void:
	for d in _debris:
		var alpha: float = clampf(d["life"] / d["max"], 0.0, 1.0)
		var col: Color = d["color"]
		var sz: float = d["size"]
		draw_rect(Rect2(d["pos"] - Vector2(sz / 2, sz / 2), Vector2(sz, sz)), Color(col.r, col.g, col.b, alpha))


# 绘制单个棋子(圆 + 名字 + 颜色,可指定中心像素)
func _draw_piece4(center: Vector2, p: Dictionary, alpha: float = 1.0) -> void:
	draw_texture_rect(_piece_texture4(), Rect2(center - Vector2(15, 15), Vector2(30, 30)), false, Color(0.3, 0.22, 0.14, alpha))
	draw_texture_rect(_piece_texture4(), Rect2(center - Vector2(14, 14), Vector2(28, 28)), false, Color(0.95, 0.9, 0.78, alpha))
	var sid: int = p["side"]
	var piece_col: Color = _side_color(sid, alpha)
	if grey_side4 == sid:
		piece_col = Color(0.55, 0.55, 0.55, alpha)
		draw_texture_rect(_piece_texture4(), Rect2(center - Vector2(14, 14), Vector2(28, 28)), false, Color(0.5, 0.5, 0.5, alpha))
	var name: String = R.PIECE_NAMES[p["type"]] if (sid == 0 or sid == 2) else R.PIECE_NAMES_BLACK[p["type"]]
	_draw_text(center + Vector2(2, -1), name, 16, piece_col)


func _draw_particles4() -> void:
	_draw_debris()


func _draw_overlay4() -> void:
	# 复制双人落位显示:选中黄圈 / 落位绿点(空位)红圈(吃子);协同棋子免费移动落点用蓝色
	var is_sync_sel4: bool = selected4.x >= 0 and selected4 in sync_pieces4
	if selected4.x >= 0:
		draw_arc(_pos_px4(selected4), 16.0, 0, TAU, 24, Color(0.95, 0.8, 0.2), 2.5)
	for m in moves4:
		var t = board[m.y][m.x]
		# 落位指示器:对方看不到的隐身子视作空位(绿点),避免暴露隐身位置
		var hidden_target4: bool = t != null and hidden_pieces4.has(m) and not _is_visible_hidden4(int(hidden_pieces4[m]) % 100)
		if is_sync_sel4:
			draw_circle(_pos_px4(m), 4.0, Color(0.3, 0.55, 0.95, 0.95))
		elif t != null and not hidden_target4:
			draw_arc(_pos_px4(m), 14.0, 0, TAU, 24, Color(0.85, 0.3, 0.25), 2.5)
		else:
			draw_circle(_pos_px4(m), 4.0, Color(0.2, 0.7, 0.3, 0.9))
	# 皇帝:同归于尽标记(紫色框 = 反制,呼吸)
	var br4 := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
	var br4_alpha := 0.7 + 0.3 * br4
	if not suicide_mark4.is_empty():
		var sp4: Vector2i = suicide_mark4["pos"]
		draw_arc(_pos_px4(sp4), 16.0 + br4 * 1.5, 0, TAU, 24, Color(0.6, 0.25, 0.85, br4_alpha), 2.5)
	# 教皇:以象为中心5×5范围内除象以外的己方棋子获得无敌(金色描边,呼吸)
	for gpos in pope_guarded4:
		draw_arc(_pos_px4(gpos), 17.0 + br4 * 1.5, 0, TAU, 32, Color(0.95, 0.8, 0.2, br4_alpha), 2.5)
	# 无敌状态:皇后全员无敌 / 皇帝指定无敌 → 金色描边(呼吸)
	if invincible_side4 >= 0 or invincible_piece4.x >= 0:
		for r in board.size():
			for c in board[r].size():
				var q = board[r][c]
				if q == null:
					continue
				var qpos := Vector2i(c, r)
				if invincible_side4 == q["side"] or qpos == invincible_piece4:
					draw_arc(_pos_px4(qpos), 17.0 + br4 * 1.5, 0, TAU, 32, Color(0.95, 0.8, 0.2, br4_alpha), 2.5)
	# 反制状态:皇后全员反制 / 教皇逆位象为中心5×5内的子反制 → 紫色描边(呼吸)
	var purple4 := Color(0.6, 0.25, 0.85, br4_alpha)
	if counter_side4 >= 0:
		for r in board.size():
			for c in board[r].size():
				var q = board[r][c]
				if q == null:
					continue
				if q["side"] == counter_side4:
					draw_arc(_pos_px4(Vector2i(c, r)), 17.0 + br4 * 1.5, 0, TAU, 32, purple4, 2.5)
	for cpos in pope_countered4:
		draw_arc(_pos_px4(cpos), 17.0 + br4 * 1.5, 0, TAU, 32, purple4, 2.5)
	# 命运之轮(逆位):协同两子淡蓝色描边(呼吸)
	for spos4 in sync_pieces4:
		draw_arc(_pos_px4(spos4), 18.0 + br4 * 1.5, 0, TAU, 32, Color(0.45, 0.8, 1.0, br4_alpha), 2.5)
	# 星星:兵免费移兵落位(蓝色)
	for t4 in free_retreat4_targets:
		draw_circle(_pos_px4(t4), 4.0, Color(0.3, 0.55, 0.95, 0.95))
	# 被将警报:各方王被将 → 红色脉冲描边(呼吸)
	for s7 in 4:
		if not in_check4.get(s7, false):
			continue
		var king7 := R.find_king(board, s7)
		if king7.x >= 0:
			draw_arc(_pos_px4(king7), 20.0 + br4 * 2.0, 0, TAU, 32, Color(1.0, 0.32, 0.25, br4_alpha), 3.0)
	# 隐者:隐身棋子只保留半透明(棋子本体绘制),不画"隐"字与描边,避免暴露隐身位置


func _handle_input4(event: InputEvent) -> void:
	if winner4 >= 0:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	# 复制双人坐标换算:四舍五入取最近交点
	var gp: Vector2 = event.position
	var c := roundi((gp.x - ORIGIN4.x) / CELL4)
	var r := roundi((gp.y - ORIGIN4.y) / CELL4)
	if c < 0 or c >= GRID4 or r < 0 or r >= GRID4:
		return
	var pos := _unrot4(Vector2i(c, r))
	# 技能目标选择优先
	if not targeting4.is_empty():
		_handle_target_click4(pos)
		return
	# 联机四人:只有轮到自己的方才能操作,且只能操作自己的棋子
	if net_role != "local" and Global.from_lobby:
		if my_side4 < 0 or current_side4() != my_side4:
			return
	var side := current_side4()
	# 倒吊人逆位:全控制期可操作其他方棋子;正位:切换操控模式(只能操控非己方棋子)
	var all_control4: bool = controlled_all_turns4 > 0 and controlled_all_owner4 == side
	var foreign4: bool = control_foreign4[side]
	# 用旋转后的逻辑坐标查棋盘(原始 c,r 是显示坐标,旋转后对应别的格子)
	var p = board[pos.y][pos.x] if R.in_board(pos, board) else null
	if net_role != "local" and Global.from_lobby:
		if p != null and p["side"] != my_side4 and selected4.x < 0 and not (all_control4 and p["side"] != my_side4) and not (foreign4 and p["side"] != my_side4):
			return
	if selected4.x >= 0:
		# 免费移动优先:星星兵落点即使也在普通走法里,也应免费执行
		if pos in free_retreat4_targets:
			_try_move4(selected4, pos, "free_retreat")
			return
		if pos in moves4:
			_try_move4(selected4, pos, "move")
			return
		if p != null and (p["side"] == side or all_control4 or (foreign4 and p["side"] != side)):
			_select4(pos)
			return
		selected4 = Vector2i(-1, -1)
		moves4 = []
		free_retreat4_targets = []
		queue_redraw()
		return
	if p != null and (p["side"] == side or all_control4 or (foreign4 and p["side"] != side)):
		_select4(pos)


func current_side4() -> int:
	return SIDE_ORDER4[turn4 % SIDE_ORDER4.size()]


func _select4(pos: Vector2i) -> void:
	# 协同棋子:本回合已免费移动过一次的不能再移动(防无限移动)
	if pos in _sync_moved4:
		return
	# 走法复用 chess_rules.raw_moves4(参数化支持 4 方方向/九宫/河界 + 技能)
	selected4 = pos
	var perks_arr: Array = [perks4[0], perks4[1], perks4[2], perks4[3]]
	moves4 = R.raw_moves4(board, pos, perks_arr)
	# 过滤:四角不可到达(棋盘四角没有渲染线)
	var filtered: Array = []
	# 隐者:隐身的子不能吃子(只能移动);倒吊人逆位:全控制棋子不能吃子;正位切换模式操控的非己方棋子可吃子
	var self_hidden4: bool = hidden_pieces4.has(pos)
	var all_control4: bool = controlled_all_turns4 > 0 and controlled_all_owner4 == current_side4()
	var foreign4: bool = control_foreign4[current_side4()]
	var mover_side4: int = board[pos.y][pos.x]["side"] if board[pos.y][pos.x] != null else -1
	var controlled4: bool = all_control4 and mover_side4 != current_side4()
	var foreign_sel4: bool = foreign4 and mover_side4 != current_side4()
	for m in moves4:
		if _is_corner4(m):
			continue
		# 隐身子 / 逆位全控制棋子:只能移到空位,不能吃子
		if board[m.y][m.x] != null and (self_hidden4 or controlled4):
			continue
		# 过滤受保护目标:皇后无敌 / 皇帝指定无敌 / 教皇象无敌
		if board[m.y][m.x] != null:
			var ts4: int = board[m.y][m.x]["side"]
			if invincible_side4 == ts4 or m == invincible_piece4:
				continue
			if pope_guarded4.has(m):
				continue
			# 正位切换模式:操控的非己方棋子不能吃操控方自己的王
			if foreign_sel4 and ts4 == current_side4() and board[m.y][m.x]["type"] == R.Type.KING:
				continue
		filtered.append(m)
	moves4 = filtered
	# 战车(被动·整局):与车相邻的棋子可落至车的可落位;选中车时可落至相邻子(含敌方)的可落位
	var cur4 := current_side4()
	var chariot_extra4: Array[Vector2i] = _chariot_boost_moves4(pos, cur4)
	for m in chariot_extra4:
		if m in moves4:
			continue
		# 与主循环一致的过滤:四角不可达/隐身子全控制不能吃/受保护目标
		if _is_corner4(m):
			continue
		if board[m.y][m.x] != null and (self_hidden4 or controlled4):
			continue
		if board[m.y][m.x] != null:
			var ts5: int = board[m.y][m.x]["side"]
			if invincible_side4 == ts5 or m == invincible_piece4:
				continue
			if pope_guarded4.has(m):
				continue
		moves4.append(m)
	# 星星:兵免费移动(蓝色,仅空格,任意方向一格)——正位每回合一次,逆位消耗蓄势
	free_retreat4_targets = []
	var p_sel = board[pos.y][pos.x]
	var star_free4: bool = false
	if p_sel != null and p_sel["type"] == R.Type.PAWN:
		if perks4[cur4].has("xingxing") and not free_retreat4_used:
			star_free4 = true
		elif perks4[cur4].has("xingxing2") and star2_charge4[cur4] > 0:
			star_free4 = true
	if star_free4:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var free_mv4: Vector2i = pos + d
			if R.in_board(free_mv4, board) and board[free_mv4.y][free_mv4.x] == null:
				free_retreat4_targets.append(free_mv4)
	queue_redraw()


# 战车(被动,四人版):返回选中 pos 的战车强化落位
func _chariot_boost_moves4(pos: Vector2i, side: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var p = board[pos.y][pos.x]
	if p == null or p["side"] != side:
		return out
	var perks_arr: Array = [perks4[0], perks4[1], perks4[2], perks4[3]]
	if p["type"] == R.Type.ROOK and perks4[side].has("zhanche2"):
		# 逆位:车的可落位 = 相邻子(含敌方)的可落位
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var np: Vector2i = pos + d
			if not R.in_board(np, board):
				continue
			var q = board[np.y][np.x]
			if q == null:
				continue
			for m in R.raw_moves4(board, np, perks_arr):
				if not m in out:
					out.append(m)
	elif perks4[side].has("zhanche"):
		# 正位:与己方车相邻 → 该车可落位并入
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var np: Vector2i = pos + d
			if not R.in_board(np, board):
				continue
			var q = board[np.y][np.x]
			if q != null and q["side"] == side and q["type"] == R.Type.ROOK:
				for m in R.raw_moves4(board, np, perks_arr):
					if not m in out:
						out.append(m)
	return out


func _is_corner4(pos: Vector2i) -> bool:
	return (pos.x < CENTER4 and pos.y < CENTER4) \
		or (pos.x > 12 and pos.y < CENTER4) \
		or (pos.x < CENTER4 and pos.y > 12) \
		or (pos.x > 12 and pos.y > 12)


# 联机四人走子入口:本地直接走;主机校验执行广播;客户端请求
func _try_move4(from: Vector2i, to: Vector2i, kind: String = "move") -> void:
	if net_role == "local" or not Global.from_lobby:
		_move4(from, to, kind)
		return
	if net_role == "host":
		var side := current_side4()
		var p = board[from.y][from.x]
		var all_ctrl4: bool = controlled_all_turns4 > 0 and controlled_all_owner4 == side
		var foreign4: bool = control_foreign4[side]
		if p == null or (p["side"] != side and not all_ctrl4 and not (foreign4 and p["side"] != side)):
			return
		if foreign4 and p["side"] != side and from in _controlled_moved4:
			return  # 正位切换模式:每子每回合限移一次
		var in_legal4: bool = to in R.raw_moves4(board, from, [perks4[0], perks4[1], perks4[2], perks4[3]])
		# 战车(被动·整局):与车相邻的棋子可落至车的可落位;选中车时可落至相邻子(含敌方)的可落位
		if not in_legal4:
			in_legal4 = to in _chariot_boost_moves4(from, side)
		# 星星免费移兵:仅空格一格;正位每回合一次,逆位消耗蓄势
		if kind == "free_retreat":
			if p == null or p["type"] != R.Type.PAWN:
				return
			var star_ok4b: bool = false
			if perks4[side].has("xingxing") and not free_retreat4_used:
				star_ok4b = true
			elif perks4[side].has("xingxing2") and star2_charge4[side] > 0:
				star_ok4b = true
			if not star_ok4b:
				return
			if board[to.y][to.x] != null:
				return
			var diff4b: Vector2i = to - from
			if absi(diff4b.x) + absi(diff4b.y) != 1:
				return
			on_move4.rpc(from, to, kind)
			return
		# 协同棋子:本回合已免费移动过一次的不能再移动(防无限移动,host 权威校验)
		if from in _sync_moved4:
			return
		if not in_legal4:
			return
		# 逆位全控制:每子每回合限移一次,不能吃子
		if all_ctrl4 and p["side"] != side:
			if from in _controlled_moved4:
				return
			if board[to.y][to.x] != null:
				return
		# 正位切换模式:操控的非己方棋子可吃子,但不能吃操控方自己的王
		if foreign4 and p["side"] != side and board[to.y][to.x] != null and board[to.y][to.x]["type"] == R.Type.KING and board[to.y][to.x]["side"] == side:
			return
		on_move4.rpc(from, to, kind)
	else:
		request_move4.rpc_id(1, from, to, kind)
		selected4 = Vector2i(-1, -1)
		moves4 = []
		free_retreat4_targets = []


# 四人走子是否会被 _move4 拦截(隐身子不能吃/审判逆位/无敌/教皇/恶魔禁吃)
# 供 _move4 校验与 AI 选走法共用;返回 true 表示该走法被拒绝
func _move4_rejected(from: Vector2i, to: Vector2i, side: int) -> bool:
	var mover = board[from.y][from.x]
	if mover == null:
		return true
	# 倒吊人正位切换模式:只能操控非己方棋子;被操控的非己方棋子每子每回合限移一次
	var cur4_side: int = current_side4()
	var foreign4: bool = control_foreign4[cur4_side] and mover["side"] != cur4_side
	if control_foreign4[cur4_side]:
		if mover["side"] == cur4_side:
			return true  # 切换模式下不能操作己方棋子
		if from in _controlled_moved4:
			return true  # 每子每回合只能移动一次
	# 逆位全控制:每子每回合限移一次
	if controlled_all_turns4 > 0 and controlled_all_owner4 == cur4_side and mover["side"] != cur4_side and from in _controlled_moved4:
		return true
	# 隐者:隐身的子不能吃子(可移动到空格)
	if hidden_pieces4.has(from) and board[to.y][to.x] != null:
		return true
	var captured = board[to.y][to.x]
	# 正位切换模式:操控的非己方棋子可吃子,但不能吃操控方自己的王
	if foreign4 and captured != null and captured["type"] == R.Type.KING and captured["side"] == cur4_side:
		return true
	# 审判逆位:敌方吃我方棋子时,判断"去掉技能后能否吃到";纯规则吃不到(靠技能增强)则禁吃
	if captured != null and perks4[captured["side"]].has("shenpan2"):
		var pure_ok4 := false
		var perks_none: Array = [{}, {}, {}, {}]
		for pure_m in R.raw_moves4(board, from, perks_none):
			if pure_m == to:
				pure_ok4 = true
				break
		if not pure_ok4:
			return true
	# 无敌/教皇/恶魔禁吃校验(审判:己方吃子无视敌方效果)
	var ignores_effect4: bool = perks4[side].has("shenpan")
	if captured != null and not ignores_effect4:
		var ts: int = captured["side"]
		if to == invincible_piece4 or invincible_side4 == ts:
			return true
		if pope_guarded4.has(to):
			return true
		if perks4[ts].has("emo") and last_eat4["side"] == side and last_eat4["type"] == mover["type"]:
			return true
		# 恶魔逆位:被吃方 2 回合内只能被该类型攻击
		if perks4[ts].has("emo2") and emo2_turns4[ts] > 0 and mover["type"] != emo2_type4[ts]:
			return true
	return false


func _move4(from: Vector2i, to: Vector2i, kind: String = "move") -> void:
	var mover = board[from.y][from.x]
	if mover == null:
		return
	var side: int = mover["side"]
	if _move4_rejected(from, to, side):
		return
	var captured = board[to.y][to.x]
	board[to.y][to.x] = mover
	board[from.y][from.x] = null
	# 移动动画:记录起点/终点像素
	_move_anims.append({
		"piece": mover,
		"from_px": _pos_px4(from),
		"to_px": _pos_px4(to),
		"t": 0.0,
		"dur": 0.22,
	})
	Global.play_sfx("move_chess", -6.0)
	# 隐者:隐身标记跟随移动(逆位持久隐身 side+100:移动后立刻破隐;普通指定两子 side+200 跟随并转移剩余回合)
	if hidden_pieces4.has(from):
		var hv4: int = hidden_pieces4[from]
		if hv4 >= 100 and hv4 < 200:
			hidden_pieces4.erase(from)
			hidden_turns4.erase(from)
		else:
			hidden_pieces4[to] = hv4
			hidden_pieces4.erase(from)
			if hidden_turns4.has(from):
				hidden_turns4[to] = hidden_turns4[from]
				hidden_turns4.erase(from)
	if hermit_active4 and not hidden_pieces4.has(to):
		hidden_pieces4[to] = side
		hermit_active4 = false
	# 倒吊人:控制权棋子走完,控制结束
	if not controlled_piece4.is_empty() and from == controlled_piece4.get("pos", Vector2i(-1, -1)):
		controlled_piece4 = {}
		controlled_turns4 = 0
	# 倒吊人逆位:全控制移动的对方棋子,记录本回合已移动
	if controlled_all_turns4 > 0 and controlled_all_owner4 == current_side4():
		var mover_after = board[to.y][to.x]
		if mover_after != null and mover_after["side"] != current_side4():
			_controlled_moved4.append(from)
	# 倒吊人正位:切换操控模式——记录已移动的非己方棋子(每子每回合限移一次)
	if control_foreign4[current_side4()]:
		var mover_f4 = board[to.y][to.x]
		if mover_f4 != null and mover_f4["side"] != current_side4():
			_controlled_moved4.append(from)
	selected4 = Vector2i(-1, -1)
	moves4 = []
	free_retreat4_targets = []
	first_moved4 = to
	# 任意兵走到棋盘正中心(8,8)变为"后"(升变规则可关闭)
	if mover["type"] == R.Type.PAWN and to == Vector2i(8, 8) and Global.game_rules.get("promotion", "queen") == "queen":
		var row: Array = board[to.y]
		var piece: Dictionary = row[to.x]
		piece["type"] = R.Type.QUEEN
		_show_status4("%s 兵晋升为后!" % SIDE_NAMES4[side])
	# 四人:记录走子
	var piece_name: String = R.PIECE_NAMES[mover["type"]] if (side == 0 or side == 2) else R.PIECE_NAMES_BLACK[mover["type"]]
	_record4_history.append({"text": "%s %s %d%d→%d%d" % [_side_short4(side), piece_name, from.x, from.y, to.x, to.y], "turn": turn4, "side": side})
	_refresh_record4()
	if captured != null:
		# 吃子特效:屏幕震动 + 被吃子粒子破碎
		_trigger_capture_effect4(captured, to)
		hidden_pieces4.erase(to)
		hidden_turns4.erase(to)
		if perks4[captured["side"]].has("emo"):
			last_eat4 = {"side": side, "type": mover["type"]}
		# 恶魔逆位:被吃方 2 回合内只能被该类型攻击
		if perks4[captured["side"]].has("emo2"):
			emo2_turns4[captured["side"]] = 2
			emo2_type4[captured["side"]] = mover["type"]
		_handle_capture4(captured, to, side)
		if captured["type"] == R.Type.KING:
			# 应用自定义规则(获胜方式/将帅被杀后处理)
			var result := _handle_king_captured4(captured["side"], side)
			if result == "winner":
				return
			if result == "continue":
				turn4 += 1
				while not alive4[current_side4()]:
					turn4 += 1
				_begin_turn4()
				return
	# 命运之轮(进阶):协同棋子移动不消耗步数,协同位置跟随棋子移动;星星免费移兵不消耗行动
	var is_free4: bool = kind == "free_retreat"
	var was_sync4: bool = from in sync_pieces4
	if not is_free4 and not was_sync4:
		actions_left4 -= 1
	elif not is_free4 and was_sync4:
		var si4 := sync_pieces4.find(from)
		if si4 >= 0:
			sync_pieces4[si4] = to
			_sync_moved4.append(to)
	# 星星免费移兵:正位标记每回合一次,逆位消耗 1 蓄势
	if is_free4:
		if perks4[side].has("xingxing"):
			free_retreat4_used = true
		elif perks4[side].has("xingxing2") and star2_charge4[side] > 0:
			star2_charge4[side] -= 1
		free_retreat4_targets = []
	# "持续一回合"效果在己方移动后清除(隐者隐身/皇后无敌/皇帝无敌)
	_expire_one_turn_effects4(side)
	queue_redraw()
	if actions_left4 <= 0:
		_end_turn4()
	else:
		_update_status4()
	_refresh_pope_guard_all4()
	_refresh_check4()
	_update_progress4()
	# 占领模式:走子后检查中心占领
	if Global.game_rules.get("win_mode", "classic") == "occupy":
		var occ := _occupy_winner4()
		if occ >= 0:
			winner4 = occ
			_show_status4("游戏结束:%s 占领中心获胜!" % SIDE_NAMES4[occ])
			_show_four_result()
			queue_redraw()


# 四人对局结束:显示结算 + "返回大厅"按钮(联机时所有人可点击回到等候大厅)
func _show_four_result() -> void:
	if four_result_root != null:
		four_result_root.queue_free()
	four_result_root = Control.new()
	four_result_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(four_result_root)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.12, 0.85)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	four_result_root.add_child(bg)
	var title := _make_label("游戏结束", 40, Color(0.95, 0.85, 0.6))
	title.position = Vector2(0, 150)
	title.size = Vector2(1280, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	four_result_root.add_child(title)
	var sub := _make_label("返回等候大厅", 20, Color(0.85, 0.82, 0.75))
	sub.position = Vector2(0, 220)
	sub.size = Vector2(1280, 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	four_result_root.add_child(sub)
	var back_btn := _make_button("返回大厅", Vector2(540, 320), Vector2(200, 52))
	back_btn.pressed.connect(func():
		Global.clear_reconnect_info()
		# 联机:复用连接直接回大厅(大厅场景用同一连接继续)
		if net_role != "local" and Global.from_lobby:
			Global.change_scene_with_fade("res://scenes/lobby.tscn")
		else:
			Global.change_scene_with_fade("res://scenes/main.tscn")
	)
	four_result_root.add_child(back_btn)


# 王被吃:按自定义规则处理,返回 "winner"(游戏结束) / "continue"(继续)
func _handle_king_captured4(dead: int, killer: int) -> String:
	var rules: Dictionary = Global.game_rules
	var win_mode: String = rules.get("win_mode", "classic")
	var kill_count: int = int(rules.get("kill_count", 2))

	if win_mode == "kills":
		# 杀棋计数:杀棋次数 +1,被杀方半场恢复开局状态(半场内敌方棋子全摧毁)
		kill_count4[dead] += 1
		_update_progress4()
		_show_status4("%s 被杀棋(%d/%d)!" % [SIDE_NAMES4[dead], kill_count4[dead], kill_count])
		_restore_arm4(dead)
		if kill_count4[dead] >= kill_count:
			winner4 = killer
			_show_status4("游戏结束:%s 达成 %d 次杀棋,获胜!" % [SIDE_NAMES4[killer], kill_count])
			_show_four_result()
			queue_redraw()
			return "winner"
		# 被杀方继续(王被吃但按规则不判负,王由杀棋方继承或重生?)
		# 规则:将帅被杀后处理在非 kills 模式;kills 模式杀棋后王移除但方继续
		alive4[dead] = true  # 继续游戏
		_remove_king_only4(dead)
		queue_redraw()
		return "continue"

	# classic / occupy:王被吃则出局
	alive4[dead] = false
	# 将帅被杀后处理(先处理棋子再移除王)
	var king_down: String = rules.get("king_down", "grey")
	if king_down == "inherit":
		_show_status4("%s 的王被吃,棋子继承给 %s!" % [SIDE_NAMES4[dead], SIDE_NAMES4[killer]])
		_inherit_pieces4(dead, killer)
	elif king_down == "grey":
		_show_status4("%s 的王被吃,棋子变灰保留!" % SIDE_NAMES4[dead])
		_grey_keep_pieces4(dead)
	else:
		_show_status4("%s 的王被吃,出局!" % SIDE_NAMES4[dead])
		_remove_pieces4(dead)
	# 检查胜利
	if win_mode == "occupy":
		# 占领:检查是否有人占中心 5 点中 3 个
		var occ_winner := _occupy_winner4()
		if occ_winner >= 0:
			winner4 = occ_winner
			_show_status4("游戏结束:%s 占领中心获胜!" % SIDE_NAMES4[occ_winner])
			_show_four_result()
			queue_redraw()
			return "winner"
	var alive_list: Array = []
	for s in alive4:
		if alive4[s]:
			alive_list.append(s)
	if alive_list.size() <= 1:
		winner4 = alive_list[0] if alive_list.size() == 1 else -1
		if winner4 >= 0:
			_show_status4("游戏结束:%s 获胜!" % SIDE_NAMES4[winner4])
		else:
			_show_status4("平局")
		_show_four_result()
		queue_redraw()
		return "winner"
	return "continue"


# 杀棋计数:半场恢复开局状态,半场内敌方棋子全部摧毁
func _restore_arm4(side: int) -> void:
	# 记录该方半场范围
	var arm: Dictionary = R.ARMS4.get(side, {})
	var min_x: int = arm.get("min_x", 0)
	var max_x: int = arm.get("max_x", 16)
	var min_y: int = arm.get("min_y", 0)
	var max_y: int = arm.get("max_y", 16)
	# 摧毁半场内所有敌方棋子
	for r in board.size():
		for c in board[r].size():
			if r >= min_y and r <= max_y and c >= min_x and c <= max_x:
				var p = board[r][c]
				if p != null and p["side"] != side:
					board[r][c] = null
	# 恢复该方棋子到开局状态
	var init := R.make_board4()
	for r in board.size():
		for c in board[r].size():
			var ip = init[r][c]
			if ip != null and ip["side"] == side:
				board[r][c] = ip
			elif ip == null and (r < min_y or r > max_y or c < min_x or c > max_x):
				pass  # 半场外不动
	queue_redraw()


# 杀棋计数:移除王(该方继续,王被吃但不判负)
func _remove_king_only4(side: int) -> void:
	for r in board.size():
		for c in board[r].size():
			var p = board[r][c]
			if p != null and p["side"] == side and p["type"] == R.Type.KING:
				board[r][c] = null


# 将帅被杀后-继承:该方棋子给杀棋方
func _inherit_pieces4(dead: int, killer: int) -> void:
	for r in board.size():
		for c in board[r].size():
			var p = board[r][c]
			if p != null and p["side"] == dead:
				p["side"] = killer
	queue_redraw()


# 将帅被杀后-变灰:棋子保留但灰化(仅移除王)
func _grey_keep_pieces4(dead: int) -> void:
	grey_side4 = dead
	# 移除王(王已被吃),其他棋子保留灰化
	for r in board.size():
		for c in board[r].size():
			var p = board[r][c]
			if p != null and p["side"] == dead and p["type"] == R.Type.KING:
				board[r][c] = null
	queue_redraw()


# 占领模式:检查是否有人占据中心 5 点中 3 个
# 占领模式 5 个中心点:中心 + 四条对角线(黑点标记)
func _occupy_spots4() -> Array:
	return [Vector2i(8, 8), Vector2i(6, 6), Vector2i(10, 10), Vector2i(6, 10), Vector2i(10, 6)]


func _occupy_winner4() -> int:
	var center_spots := _occupy_spots4()
	var counts := {0: 0, 1: 0, 2: 0, 3: 0}
	for spot in center_spots:
		var p = board[spot.y][spot.x]
		if p != null:
			counts[p["side"]] = counts.get(p["side"], 0) + 1
	for s in counts:
		if counts[s] >= 3 and alive4[s]:
			return s
	return -1


func _handle_capture4(captured: Dictionary, captured_pos: Vector2i, attacker_side: int) -> void:
	var victim_side: int = captured["side"]
	# 反制:被吃时同归于尽
	var counter_triggered: bool = false
	if suicide_mark4.get("pos") == captured_pos and suicide_mark4.get("side") == victim_side:
		counter_triggered = true
		suicide_mark4 = {}
		_show_status4("皇帝:同归于尽!")
	elif victim_side == counter_side4:
		counter_triggered = true
		_show_status4("皇后:反制,同归于尽!")
	elif pope_countered4.has(captured_pos):
		counter_triggered = true
		_show_status4("教皇:反制,同归于尽!")
	if counter_triggered:
		board[captured_pos.y][captured_pos.x] = null
	# 恋人:己方每被吃 2 子,复活一枚到出生位置
	revive_count4[victim_side] += 1
	if perks4[victim_side].has("lianren") and revive_count4[victim_side] % 2 == 0:
		_revive_piece4(victim_side)
	# 恋人(逆位):被吃充能(需求 2,使用后其他技能完成冷却/充能)
	if perks4[victim_side].has("lianren2"):
		lianren2_charge4[victim_side] = mini(lianren2_charge4[victim_side] + 1, 2)
	# 皇后/死亡:被吃充能(皇后上限 1;逆位力量可累计至 3 倍)
	var queen_cap4 := 3 if perks4[victim_side].has("liliang2") else 1
	if perks4[victim_side].has("huanghou") or perks4[victim_side].has("huanghou2"):
		queen_charge4[victim_side] = mini(queen_charge4[victim_side] + 1, queen_cap4)
	var siwang_cap4 := 9 if perks4[victim_side].has("liliang2") else 3
	if perks4[victim_side].has("siwang") or perks4[victim_side].has("siwang2"):
		siwang_charge4[victim_side] = mini(siwang_charge4[victim_side] + 1, siwang_cap4)


func _revive_piece4(side: int) -> void:
	var targets: Array[Vector2i] = []
	for i in 9:
		var lp := _line_pos4(side, i)
		if board[lp.y][lp.x] == null:
			targets.append(lp)
	if targets.is_empty():
		return
	board[targets[0].y][targets[0].x] = R.make_piece(side, R.Type.PAWN)
	_show_status4("生生不息:复活一枚兵")
	queue_redraw()


func _destroy_random_enemy4(victim_side: int, n: int) -> void:
	var candidates: Array[Vector2i] = []
	for r in board.size():
		for c in board[r].size():
			var q = board[r][c]
			if q != null and q["side"] != victim_side and q["type"] != R.Type.KING:
				candidates.append(Vector2i(c, r))
	candidates.shuffle()
	for i in mini(n, candidates.size()):
		var v: Vector2i = candidates[i]
		board[v.y][v.x] = null
	_show_status4("恋人:随机摧毁对方 %d 枚棋子" %  mini(n, candidates.size()))
	queue_redraw()


func _remove_pieces4(dead: int) -> void:
	for r in board.size():
		for c in board[r].size():
			var p = board[r][c]
			if p != null and p["side"] == dead:
				board[r][c] = null


func _update_status4() -> void:
	if status_label != null:
		var side := current_side4()
		var check_txt := "  ⚠ 被将!" if in_check4.get(side, false) else ""
		if my_side4 >= 0:
			# 联机:轮到自己的方显示"你的回合"(呼吸),否则等待对方
			if side == my_side4:
				status_label.text = "你的回合" + check_txt
				_my_turn_breath4 = true
			else:
				var nm2: String = ""
				if Global.lobby_players.has(side):
					nm2 = Global.lobby_players[side].get("name", SIDE_NAMES4[side])
				status_label.text = "等待 %s..." % nm2 + check_txt
				_my_turn_breath4 = false
		else:
			# 本地四人:显示当前方回合名
			var nm: String = ""
			if Global.lobby_players.has(side):
				nm = Global.lobby_players[side].get("name", "")
			if nm.is_empty():
				nm = SIDE_NAMES4[side]
			status_label.text = "回合：" + nm + check_txt
			_my_turn_breath4 = false
		status_label.modulate = _side_color(side)
	_refresh_perk_panels4()

# 四人:状态提示(技能反馈等),1 秒后恢复回合显示
func _show_status4(msg: String) -> void:
	if status_label != null:
		status_label.text = msg
		status_label.modulate = Color(1, 1, 1)
		_status4_until = Time.get_ticks_msec() / 1000.0 + 1.0


func _turn_info4(side: int) -> String:
	var parts: Array[String] = []
	if actions_left4 > 1:
		parts.append("可动 %d 次" % actions_left4)
	if invincible_side4 == side:
		parts.append("全员无敌")
	if counter_side4 == side:
		parts.append("反制")
	if not hidden_pieces4.is_empty():
		parts.append("有隐身")
	if not parts.is_empty():
		return "(" + "、".join(parts) + ")"
	return ""


# ==================== 四人回合状态机(复制双人逻辑,吃王获胜无将军) ====================

# "持续一回合"效果在己方移动后清除(四人版,复制双人逻辑)
func _expire_one_turn_effects4(side: int) -> void:
	var hidden_rm: Array[Vector2i] = []
	for pos in hidden_pieces4:
		if hidden_pieces4[pos] == side:
			hidden_rm.append(pos)
		elif hidden_pieces4[pos] == side + 200:
			hidden_turns4[pos] -= 1
			if hidden_turns4[pos] <= 0:
				hidden_rm.append(pos)
	for pos in hidden_rm:
		hidden_pieces4.erase(pos)
		hidden_turns4.erase(pos)
	if invincible_side4 == side:
		invincible_side_turns4 -= 1
		if invincible_side_turns4 <= 0:
			invincible_side4 = -1
			invincible_side_turns4 = 0
	if invincible_piece_side4 == side:
		invincible_piece_turns4 -= 1
		if invincible_piece_turns4 <= 0:
			invincible_piece4 = Vector2i(-1, -1)
			invincible_piece_side4 = -1
			invincible_piece_turns4 = 0
	if counter_side4 == side:
		counter_side4 = -1

func _begin_turn4() -> void:
	var side := current_side4()
	for id in skill_cd4[side].keys():
		skill_cd4[side][id] = maxi(skill_cd4[side][id] - 1, 0)
	if perks4[side].has("shijie"):
		_apply_dice4(side, side)
	if perks4[side].has("shijie2"):
		_apply_dice4(side, _next_alive4(side))
	# 注:隐者隐身/皇后无敌/皇帝无敌/皇后逆位反制等"持续一回合"效果,改为己方移动后清除(见 _move4)
	sync_pieces4 = []
	_sync_moved4 = []
	hermit_active4 = hermit_pending4
	hermit_pending4 = false
	# 倒吊人逆位:全控制回合递减(在控制方回合开始减)
	if controlled_all_turns4 > 0 and controlled_all_owner4 == side:
		controlled_all_turns4 -= 1
		_controlled_moved4 = []
		if controlled_all_turns4 <= 0:
			controlled_all_owner4 = -1
	# 倒吊人正位:切换操控模式(每子每回合限移一次)
	if control_foreign4[side]:
		_controlled_moved4 = []
	# 恶魔逆位:免疫回合递减
	for s4 in 4:
		if emo2_turns4[s4] > 0:
			emo2_turns4[s4] -= 1
			if emo2_turns4[s4] <= 0:
				emo2_type4[s4] = -1
	# 隐者(进阶):己方隐身子每回合每子 10% 概率破隐(逆位持久隐身标记为 side+100)
	if not hidden_pieces4.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var reveal4: Array[Vector2i] = []
		for pos in hidden_pieces4:
			if hidden_pieces4[pos] == side + 100 and rng.randf() < 0.1:
				reveal4.append(pos)
		for pos in reveal4:
			hidden_pieces4.erase(pos)
	if all_hidden_turns4[side] > 0:
		all_hidden_turns4[side] -= 1
		if all_hidden_turns4[side] <= 0:
			hidden_pieces4.clear()
	if skip_next_turn4[side]:
		skip_next_turn4[side] = false
		_show_status4("%s 被节制跳过本回合" %  SIDE_NAMES4[side])
		_end_turn4()
		return
	_refresh_judgement4(side)
	_refresh_pope_guard_all4()
	actions_left4 = _turn_action_cap4()
	if extra_turn4[side]:
		extra_turn4[side] = false
		actions_left4 += 1
	first_moved4 = Vector2i(-1, -1)
	free_retreat4_used = false
	free_retreat4_targets = []
	_refresh_perk_panels4()
	_update_status4()
	_refresh_check4()
	queue_redraw()
	# 机器人补位:轮到 AI 方自动走子(主机权威执行并广播)
	_maybe_ai4()


# 四人:当前方是机器人时自动走子(仅 host 执行并广播)
func _maybe_ai4() -> void:
	if winner4 >= 0 or phase != Phase.PLAY:
		return
	if net_role != "host" and net_role != "local":
		return
	var side := current_side4()
	var info: Dictionary = Global.lobby_players.get(side, {})
	if not bool(info.get("is_ai", false)):
		return
	# 延迟走子,模拟思考
	await get_tree().create_timer(0.6).timeout
	if winner4 >= 0 or phase != Phase.PLAY or current_side4() != side:
		return
	var perks_arr: Array = [perks4[0], perks4[1], perks4[2], perks4[3]]
	var mv := _choose_ai_move4(side, perks_arr)
	if mv.is_empty():
		return
	if net_role == "host":
		on_move4.rpc(mv["from"], mv["to"])
	else:
		_try_move4(mv["from"], mv["to"])


# 四人 AI 选走法:排除会被审判逆位驳回的技能增强吃子(否则 _move4 驳回后 AI 卡住不思考)
func _choose_ai_move4(side: int, perks_arr: Array) -> Dictionary:
	var mv: Dictionary = AI.choose_move4(board, side, perks_arr)
	if mv.is_empty():
		return {}
	var from: Vector2i = mv["from"]
	var to: Vector2i = mv["to"]
	# 首选走法会被 _move4 拦截(无敌/教皇/审判逆位/恶魔禁吃/隐身子吃子):改选其它不被拦截的走法
	if _move4_rejected(from, to, side):
		var candidates: Array = []
		for r in board.size():
			for c in board[r].size():
				var q = board[r][c]
				if q == null or q["side"] != side:
					continue
				var f := Vector2i(c, r)
				for m in R.raw_moves4(board, f, perks_arr):
					if _move4_rejected(f, m, side):
						continue
					candidates.append({"from": f, "to": m, "score": _ai4_score(f, m, side)})
		if candidates.is_empty():
			return {}
		candidates.sort_custom(func(a, b): return a["score"] > b["score"])
		var pick: Dictionary = candidates[0]
		return {"from": pick["from"], "to": pick["to"]}
	return mv


func _ai4_score(from: Vector2i, to: Vector2i, side: int) -> float:
	var res := R.apply_move(board, from, to)
	var cap = res.get("captured", null)
	var s := 0.0
	if cap != null:
		s += 15.0
	return s + (randi() % 3) * 0.1


func _turn_action_cap4() -> int:
	var n := 1
	if extra_move4[current_side4()]:
		n += 1
	return n


func _end_turn4() -> void:
	extra_move4[current_side4()] = false
	turn4 += 1
	while not alive4[current_side4()]:
		turn4 += 1
	# 注:倒吊人控制权(正位)不在此递减——与双人一致,在被控子移动后清除(见 _move4);
	# 逆位全控制回合在 _begin_turn4 按控制方回合递减
	_begin_turn4()


func _next_alive4(side: int) -> int:
	var idx := SIDE_ORDER4.find(side)
	if idx < 0:
		return side
	for k in range(1, 5):
		var s: int = SIDE_ORDER4[(idx + k) % 4]
		if alive4[s]:
			return s
	return side


func _refresh_judgement4(side: int) -> void:
	var target := _next_alive4(side)
	disabled_skills4[target] = ""
	# 审判逆位:被动效果(敌方不能以技能吃我方棋子),无每回合动作
	if not perks4[side].has("shenpan"):
		return
	var actives: Array = []
	for id in perks4[target]:
		if _is_active_skill(id):
			actives.append(id)
	if actives.is_empty():
		return
	disabled_skills4[target] = actives.pick_random()
	_show_status4("审判:%s 的[%s]被禁用" %  [SIDE_NAMES4[target], perks_data[disabled_skills4[target]]["name"]])


func _refresh_pope_guard4(side: int) -> void:
	var has_pope4: bool = perks4[side].has("jiaohuang")
	var has_pope24: bool = perks4[side].has("jiaohuang2")
	if not has_pope4 and not has_pope24:
		return
	for r in board.size():
		for c in board[r].size():
			var p = board[r][c]
			if p == null or p["side"] != side or p["type"] != R.Type.ELEPHANT:
				continue
			var pos := Vector2i(c, r)
			# 以象为中心的 5×5 范围
			for dr in range(-2, 3):
				for dc in range(-2, 3):
					var gpos: Vector2i = pos + Vector2i(dc, dr)
					if not R.in_board(gpos, board):
						continue
					var gp = board[gpos.y][gpos.x]
					if gpos == pos:
						# 象自身:正位不获得无敌;逆位获得反制
						if has_pope24:
							pope_countered4[gpos] = true
						continue
					if gp == null:
						continue
					# 正位:范围内己方棋子无敌(排除象自身及其他象,避免象互保无法被吃)
					if has_pope4 and gp["side"] == side and gp["type"] != R.Type.ELEPHANT:
						pope_guarded4[gpos] = true
					if has_pope24:
						pope_countered4[gpos] = true  # 逆位:范围内任意子反制(含敌方)


# 刷新所有存活方教皇效果(先清空再累加,避免多次调用互相覆盖)
func _refresh_pope_guard_all4() -> void:
	pope_guarded4.clear()
	pope_countered4.clear()
	for s in 4:
		if alive4[s]:
			_refresh_pope_guard4(s)


# ==================== 联机四人:主机权威状态同步(复制双人逻辑,4 方版) ====================

func _state_to_data4() -> Dictionary:
	var caps: Array = []
	for rec in captured_history4:
		caps.append({
			"side": rec["side"], "type": rec["type"],
			"pos": [rec["pos"].x, rec["pos"].y],
			"birth_pos": [rec["birth_pos"].x, rec["birth_pos"].y],
		})
	var hidden: Array = []
	for pos in hidden_pieces4:
		hidden.append([pos.x, pos.y, int(hidden_pieces4[pos])])
	var h_turns4: Array = []
	for pos in hidden_turns4:
		h_turns4.append([pos.x, pos.y, int(hidden_turns4[pos])])
	var cds := {}
	for s in skill_cd4:
		cds[str(s)] = skill_cd4[s].duplicate()
	var perks_all := {}
	for s in perks4:
		perks_all[str(s)] = perks4[s].duplicate()
	return {
		"board": _board_to_json(board),
		"turn4": turn4,
		"phase": phase,
		"winner4": winner4,
		"alive4": {"0": alive4[0], "1": alive4[1], "2": alive4[2], "3": alive4[3]},
		"actions_left4": actions_left4,
		"first_moved4": [first_moved4.x, first_moved4.y],
		"free_retreat4_used": free_retreat4_used,
		"skill_cd4": cds,
		"captured_history4": caps,
		"revive_count4": {"0": revive_count4[0], "1": revive_count4[1], "2": revive_count4[2], "3": revive_count4[3]},
		"queen_charge4": {"0": queen_charge4[0], "1": queen_charge4[1], "2": queen_charge4[2], "3": queen_charge4[3]},
		"extra_turn4": {"0": extra_turn4[0], "1": extra_turn4[1], "2": extra_turn4[2], "3": extra_turn4[3]},
		"skip_next_turn4": {"0": skip_next_turn4[0], "1": skip_next_turn4[1], "2": skip_next_turn4[2], "3": skip_next_turn4[3]},
		"extra_move4": {"0": extra_move4[0], "1": extra_move4[1], "2": extra_move4[2], "3": extra_move4[3]},
		"all_hidden_turns4": {"0": all_hidden_turns4[0], "1": all_hidden_turns4[1], "2": all_hidden_turns4[2], "3": all_hidden_turns4[3]},
		"suicide_mark4": {} if suicide_mark4.is_empty() else {"pos": [suicide_mark4["pos"].x, suicide_mark4["pos"].y], "side": suicide_mark4["side"]},
		"hidden_pieces4": hidden,
		"hidden_turns4": h_turns4,
		"invincible_side4": invincible_side4,
		"invincible_side_turns4": invincible_side_turns4,
		"invincible_piece4": [invincible_piece4.x, invincible_piece4.y],
		"invincible_piece_side4": invincible_piece_side4,
		"invincible_piece_turns4": invincible_piece_turns4,
		"counter_side4": counter_side4,
		"hermit_pending4": hermit_pending4,
		"hermit_active4": hermit_active4,
		"controlled_piece4": {} if controlled_piece4.is_empty() else {"pos": [controlled_piece4["pos"].x, controlled_piece4["pos"].y], "owner": controlled_piece4["owner"]},
		"disabled_skills4": {"0": disabled_skills4[0], "1": disabled_skills4[1], "2": disabled_skills4[2], "3": disabled_skills4[3]},
		"last_eat4": {"side": last_eat4["side"], "type": last_eat4["type"]},
		"emo2_turns4": {"0": emo2_turns4[0], "1": emo2_turns4[1], "2": emo2_turns4[2], "3": emo2_turns4[3]},
		"emo2_type4": {"0": emo2_type4[0], "1": emo2_type4[1], "2": emo2_type4[2], "3": emo2_type4[3]},
		"siwang_charge4": {"0": siwang_charge4[0], "1": siwang_charge4[1], "2": siwang_charge4[2], "3": siwang_charge4[3]},
		"lianren2_charge4": {"0": lianren2_charge4[0], "1": lianren2_charge4[1], "2": lianren2_charge4[2], "3": lianren2_charge4[3]},
		"star2_charge4": {"0": star2_charge4[0], "1": star2_charge4[1], "2": star2_charge4[2], "3": star2_charge4[3]},
		"sync_pieces4": _sync_pieces_to_data4(),
		"controlled_turns4": controlled_turns4,
		"control_foreign4": {"0": control_foreign4[0], "1": control_foreign4[1], "2": control_foreign4[2], "3": control_foreign4[3]},
		"pope_guarded4": _pope_to_data4(),
		"pope_countered4": _pope2_to_data4(),
		"perks4": perks_all,
		"record4_history": _record4_history,
	}


func _sync_pieces_to_data4() -> Array:
	var arr: Array = []
	for q in sync_pieces4:
		arr.append([q.x, q.y])
	return arr


func _pope_to_data4() -> Array:
	var arr: Array = []
	for pos in pope_guarded4:
		arr.append([pos.x, pos.y])
	return arr


func _pope2_to_data4() -> Array:
	var arr: Array = []
	for pos in pope_countered4:
		arr.append([pos.x, pos.y])
	return arr


func _apply_state_data4(data: Dictionary) -> void:
	board = _board_from_json(data["board"])
	turn4 = int(data["turn4"])
	phase = int(data["phase"])
	winner4 = int(data.get("winner4", -1))
	alive4 = {0: bool(data["alive4"]["0"]), 1: bool(data["alive4"]["1"]), 2: bool(data["alive4"]["2"]), 3: bool(data["alive4"]["3"])}
	actions_left4 = int(data["actions_left4"])
	first_moved4 = Vector2i(int(data["first_moved4"][0]), int(data["first_moved4"][1]))
	free_retreat4_used = bool(data.get("free_retreat4_used", false))
	skill_cd4 = {}
	for s in data["skill_cd4"]:
		skill_cd4[int(s)] = {}
		for id in data["skill_cd4"][s]:
			skill_cd4[int(s)][id] = int(data["skill_cd4"][s][id])
	captured_history4 = []
	for rec in data["captured_history4"]:
		captured_history4.append({
			"side": int(rec["side"]), "type": int(rec["type"]),
			"pos": Vector2i(int(rec["pos"][0]), int(rec["pos"][1])),
			"birth_pos": Vector2i(int(rec["birth_pos"][0]), int(rec["birth_pos"][1])),
		})
	revive_count4 = {0: int(data["revive_count4"]["0"]), 1: int(data["revive_count4"]["1"]), 2: int(data["revive_count4"]["2"]), 3: int(data["revive_count4"]["3"])}
	queen_charge4 = {0: int(data["queen_charge4"]["0"]), 1: int(data["queen_charge4"]["1"]), 2: int(data["queen_charge4"]["2"]), 3: int(data["queen_charge4"]["3"])}
	extra_turn4 = {0: bool(data["extra_turn4"]["0"]), 1: bool(data["extra_turn4"]["1"]), 2: bool(data["extra_turn4"]["2"]), 3: bool(data["extra_turn4"]["3"])}
	skip_next_turn4 = {0: bool(data["skip_next_turn4"]["0"]), 1: bool(data["skip_next_turn4"]["1"]), 2: bool(data["skip_next_turn4"]["2"]), 3: bool(data["skip_next_turn4"]["3"])}
	extra_move4 = {0: bool(data["extra_move4"]["0"]), 1: bool(data["extra_move4"]["1"]), 2: bool(data["extra_move4"]["2"]), 3: bool(data["extra_move4"]["3"])}
	all_hidden_turns4 = {0: int(data["all_hidden_turns4"]["0"]), 1: int(data["all_hidden_turns4"]["1"]), 2: int(data["all_hidden_turns4"]["2"]), 3: int(data["all_hidden_turns4"]["3"])}
	if data["suicide_mark4"].is_empty():
		suicide_mark4 = {}
	else:
		var sm = data["suicide_mark4"]
		suicide_mark4 = {"pos": Vector2i(int(sm["pos"][0]), int(sm["pos"][1])), "side": int(sm["side"])}
	hidden_pieces4 = {}
	for h in data["hidden_pieces4"]:
		hidden_pieces4[Vector2i(int(h[0]), int(h[1]))] = int(h[2])
	hidden_turns4 = {}
	for ht in data.get("hidden_turns4", []):
		hidden_turns4[Vector2i(int(ht[0]), int(ht[1]))] = int(ht[2])
	invincible_side4 = int(data["invincible_side4"])
	invincible_side_turns4 = int(data.get("invincible_side_turns4", 0))
	invincible_piece4 = Vector2i(int(data["invincible_piece4"][0]), int(data["invincible_piece4"][1]))
	invincible_piece_side4 = int(data.get("invincible_piece_side4", -1))
	invincible_piece_turns4 = int(data.get("invincible_piece_turns4", 0))
	counter_side4 = int(data.get("counter_side4", -1))
	hermit_pending4 = bool(data.get("hermit_pending4", false))
	hermit_active4 = bool(data.get("hermit_active4", false))
	if data.get("controlled_piece4", {}).is_empty():
		controlled_piece4 = {}
	else:
		var cpi = data["controlled_piece4"]
		controlled_piece4 = {"pos": Vector2i(int(cpi["pos"][0]), int(cpi["pos"][1])), "owner": int(cpi["owner"])}
	disabled_skills4 = {}
	for i in 4:
		disabled_skills4[i] = str(data.get("disabled_skills4", {}).get(str(i), ""))
	var le = data.get("last_eat4", {})
	last_eat4 = {"side": int(le.get("side", -1)), "type": int(le.get("type", -1))}
	emo2_turns4 = {0: int(data.get("emo2_turns4", {}).get("0", 0)), 1: int(data.get("emo2_turns4", {}).get("1", 0)), 2: int(data.get("emo2_turns4", {}).get("2", 0)), 3: int(data.get("emo2_turns4", {}).get("3", 0))}
	emo2_type4 = {0: int(data.get("emo2_type4", {}).get("0", -1)), 1: int(data.get("emo2_type4", {}).get("1", -1)), 2: int(data.get("emo2_type4", {}).get("2", -1)), 3: int(data.get("emo2_type4", {}).get("3", -1))}
	siwang_charge4 = {0: int(data.get("siwang_charge4", {}).get("0", 0)), 1: int(data.get("siwang_charge4", {}).get("1", 0)), 2: int(data.get("siwang_charge4", {}).get("2", 0)), 3: int(data.get("siwang_charge4", {}).get("3", 0))}
	lianren2_charge4 = {0: int(data.get("lianren2_charge4", {}).get("0", 0)), 1: int(data.get("lianren2_charge4", {}).get("1", 0)), 2: int(data.get("lianren2_charge4", {}).get("2", 0)), 3: int(data.get("lianren2_charge4", {}).get("3", 0))}
	star2_charge4 = {0: int(data.get("star2_charge4", {}).get("0", 0)), 1: int(data.get("star2_charge4", {}).get("1", 0)), 2: int(data.get("star2_charge4", {}).get("2", 0)), 3: int(data.get("star2_charge4", {}).get("3", 0))}
	sync_pieces4 = []
	for q in data.get("sync_pieces4", []):
		sync_pieces4.append(Vector2i(int(q[0]), int(q[1])))
	controlled_turns4 = int(data.get("controlled_turns4", 0))
	control_foreign4 = {
		0: bool(data.get("control_foreign4", {}).get("0", false)),
		1: bool(data.get("control_foreign4", {}).get("1", false)),
		2: bool(data.get("control_foreign4", {}).get("2", false)),
		3: bool(data.get("control_foreign4", {}).get("3", false)),
	}
	pope_guarded4 = {}
	for pg in data.get("pope_guarded4", []):
		pope_guarded4[Vector2i(int(pg[0]), int(pg[1]))] = true
	pope_countered4 = {}
	for pc in data.get("pope_countered4", []):
		pope_countered4[Vector2i(int(pc[0]), int(pc[1]))] = true
	if data.has("perks4"):
		perks4 = {}
		for side_str in data["perks4"]:
			perks4[int(side_str)] = data["perks4"][side_str].duplicate()
	selected4 = Vector2i(-1, -1)
	moves4 = []
	# 对局记录同步:以主机 record4_history 为准(含双方技能使用)
	if data.has("record4_history"):
		_record4_history = []
		for rec in data["record4_history"]:
			_record4_history.append({"text": str(rec.get("text", "")), "turn": int(rec.get("turn", 0)), "side": int(rec.get("side", -1))})
		_refresh_record4()
	_refresh_perk_panels4()
	_update_status4()
	_refresh_check4()
	queue_redraw()
	# 四人:对局结束(有胜者)时显示结算,所有端一致(含客户端收到广播后)
	if winner4 >= 0:
		_show_four_result()


# 主机把完整 4 方状态广播给所有客户端
func _broadcast_state4() -> void:
	if net_role != "host":
		return
	sync_state4.rpc(_state_to_data4())


@rpc("authority", "reliable")
func sync_state4(data: Dictionary) -> void:
	_apply_state_data4(data)
	# 重连:主机告知本进程的 side(进程重启后 lobby_players 为空,无法自查)
	if Global.reconnect_mode and data.has("my_side4"):
		var side := int(data["my_side4"])
		if side >= 0:
			my_side4 = side
			own_side = side
			_view_rot4 = {0: 0, 1: 1, 2: 2, 3: 3}.get(side, 0)
			Global.reconnect_mode = false
			if net_wait_label != null:
				net_wait_label.queue_free()
				net_wait_label = null
			queue_redraw()


# 客户端 → 主机:请求走子(四人)
@rpc("any_peer", "reliable")
func request_move4(from: Vector2i, to: Vector2i, kind: String = "move") -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	var side := _side_for_peer4(pid)
	if side < 0 or current_side4() != side:
		return
	var p = board[from.y][from.x]
	if p == null or p["side"] != side:
		return
	# 协同棋子:本回合已免费移动过一次的不能再移动(防无限移动)
	if from in _sync_moved4:
		return
	# 走法校验
	var perks_arr: Array = [perks4[0], perks4[1], perks4[2], perks4[3]]
	var in_legal4b: bool = to in R.raw_moves4(board, from, perks_arr)
	# 战车(被动·整局):与车相邻的棋子可落至车的可落位;选中车时可落至相邻子(含敌方)的可落位
	if not in_legal4b:
		in_legal4b = to in _chariot_boost_moves4(from, side)
	if not in_legal4b:
		return
	# 星星免费移兵:仅空格一格,任意方向;正位每回合一次,逆位消耗蓄势
	if kind == "free_retreat":
		if p["type"] != R.Type.PAWN:
			return
		var star_ok4: bool = false
		if perks4[side].has("xingxing") and not free_retreat4_used:
			star_ok4 = true
		elif perks4[side].has("xingxing2") and star2_charge4[side] > 0:
			star_ok4 = true
		if not star_ok4:
			return
		if board[to.y][to.x] != null:
			return
		var diff4: Vector2i = to - from
		if absi(diff4.x) + absi(diff4.y) != 1:
			return
		on_move4.rpc(from, to, kind)
		return
	if hidden_pieces4.has(from) and board[to.y][to.x] != null:
		return
	if board[to.y][to.x] != null:
		var ts: int = board[to.y][to.x]["side"]
		if to == invincible_piece4 or invincible_side4 == ts:
			return
		if pope_guarded4.has(to):
			return
	on_move4.rpc(from, to, kind)


# 主机 → 所有人:广播走子(四人,含主机本地)
@rpc("authority", "call_local", "reliable")
func on_move4(from: Vector2i, to: Vector2i, kind: String = "move") -> void:
	_move4(from, to, kind)
	_broadcast_state4()


func _side_for_peer4(pid: int) -> int:
	for side in four_side_to_peer:
		if four_side_to_peer[side] == pid:
			return int(side)
	return -1


# 客户端 → 主机:请求主动技能(四人)
@rpc("any_peer", "reliable")
func request_skill4(perk_id: String, params: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	var side := _side_for_peer4(pid)
	if side < 0 or current_side4() != side:
		return
	_execute_skill4(perk_id, side, params)
	_broadcast_state4()


# 主机 → 所有人:广播技能(四人)
@rpc("authority", "call_local", "reliable")
func on_skill4(perk_id: String, side: int, params: Dictionary) -> void:
	_execute_skill4(perk_id, side, params)
	_broadcast_state4()


# 主机 → 所有人:广播技能释放提醒(屏幕中央大字,四人)
@rpc("authority", "call_local", "reliable")
func notify_skill_used4(perk_id: String, side: int) -> void:
	_show_skill_announce(perk_id, side)


# 统一执行四人主动技能(host 权威)
func _execute_skill4(perk_id: String, side: int, params: Dictionary) -> void:
	if phase != Phase.PLAY:
		return
	if actions_left4 < _turn_action_cap4():
		return
	if disabled_skills4[side] == perk_id:
		return
	var cd: int = skill_cd4[side].get(perk_id, 0)
	if cd > 0:
		return
	if perk_id == "huanghou" and queen_charge4[side] <= 0:
		return
	if perk_id == "siwang" and siwang_charge4[side] <= 0:
		return
	if not params.is_empty() and params.get("pos", []) != []:
		var pos := Vector2i(int(params["pos"][0]), int(params["pos"][1]))
		match perk_id:
			"huangdi":
				var p1 = board[pos.y][pos.x]
				if p1 == null or p1["side"] != side:
					return
				invincible_piece4 = pos
				invincible_piece_side4 = side
				invincible_piece_turns4 = 3
				_apply_skill_cd4("huangdi", side)
				_record_skill4(side, "huangdi")
				notify_skill_used4.rpc("huangdi", side)
				_show_status4("皇帝:该子无敌(持续3回合)")
				_consume_turn_after_skill4()
				queue_redraw()
				return
			"huangdi2":
				var p2 = board[pos.y][pos.x]
				if p2 == null or p2["side"] != side:
					return
				suicide_mark4 = {"pos": pos, "side": side}
				_apply_skill_cd4("huangdi2", side)
				_record_skill4(side, "huangdi2")
				notify_skill_used4.rpc("huangdi2", side)
				_show_status4("皇帝:标记棋子,被吃时同归于尽")
				_consume_turn_after_skill4()
				queue_redraw()
				return
			"siwang":
				var p3 = board[pos.y][pos.x]
				if p3 == null or p3["side"] != side:
					return
				if siwang_charge4[side] <= 0:
					return
				siwang_charge4[side] -= 1
				_destroy_same_type4(pos, side)
				_record_skill4(side, "siwang")
				notify_skill_used4.rpc("siwang", side)
				_consume_turn_after_skill4()
				queue_redraw()
				return
			"diaodiao", "diaodiao2":
				var p4 = board[pos.y][pos.x]
				if p4 == null or p4["side"] == side:
					return
				controlled_piece4 = {"pos": pos, "owner": side}
				controlled_turns4 = 3 if perk_id == "diaodiao2" else 1
				_apply_skill_cd4(perk_id, side)
				_record_skill4(side, perk_id)
				notify_skill_used4.rpc(perk_id, side)
				_show_status4("倒吊人:获得对方棋子控制权")
				_consume_turn_after_skill4()
				queue_redraw()
				return
	# 隐者(普通):指定两子隐身两回合(a/b 参数)
	if perk_id == "yinzhe" and params.has("a") and params.has("b"):
		var ha := Vector2i(int(params["a"][0]), int(params["a"][1]))
		var hb := Vector2i(int(params["b"][0]), int(params["b"][1]))
		var pa = board[ha.y][ha.x]
		var pb = board[hb.y][hb.x]
		if pa == null or pa["side"] != side or pb == null or pb["side"] != side or ha == hb:
			return
		_apply_hermit_target4(ha, hb, side)
		_apply_skill_cd4("yinzhe", side)
		_record_skill4(side, "yinzhe")
		notify_skill_used4.rpc("yinzhe", side)
		_show_status4("隐者:指定两子隐身两回合")
		_consume_turn_after_skill4()
		queue_redraw()
		return
	# 非目标型或未走目标分支
	if not _is_targeting_skill(perk_id):
		_activate_skill4(perk_id, side)
	else:
		_activate_skill4(perk_id, side)


func _apply_dice4(side: int, target_side: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for r in board.size():
		for c in board[r].size():
			var p = board[r][c]
			if p == null or p["side"] != target_side or p["type"] == R.Type.KING:
				continue
			if rng.randf() < 0.1:
				board[r][c] = R.make_piece(target_side, _random_piece_type())
	queue_redraw()

# ==================== 四人主动技能效果(复制双人,坐标按四方半场) ====================

func _skill_priestess4(perk_id: String, side: int) -> void:
	if perk_id == "nvjisi2":
		# 逆位:底线生成随机棋子(去掉兵和士)
		var slots: Array[Vector2i] = []
		var back: Array[Vector2i] = []
		match side:
			1: for i in 9: back.append(Vector2i(4 + i, 0))
			0: for i in 9: back.append(Vector2i(4 + i, 16))
			2: for i in 9: back.append(Vector2i(0, 4 + i))
			3: for i in 9: back.append(Vector2i(16, 4 + i))
		for pos in back:
			if board[pos.y][pos.x] == null:
				slots.append(pos)
		if slots.is_empty():
			_show_status4("底线已满,无法生成")
			return
		var pos: Vector2i = slots.pick_random()
		board[pos.y][pos.x] = R.make_piece(side, _random_piece_type(true))
		_show_status4("女祭司:底线生成一个随机棋子(兵士除外)")
	else:
		# 正位:所有兵前进一格 + 补全兵线
		var fwd4 := R.pawn_fwd(side)
		var pawns4: Array[Vector2i] = []
		for r in board.size():
			for c in board[r].size():
				var p = board[r][c]
				if p != null and p["side"] == side and p["type"] == R.Type.PAWN:
					pawns4.append(Vector2i(c, r))
		for pos in pawns4:
			var tgt4: Vector2i = pos + fwd4
			if R.in_board(tgt4, board) and board[tgt4.y][tgt4.x] == null:
				board[tgt4.y][tgt4.x] = board[pos.y][pos.x]
				board[pos.y][pos.x] = null
		for i in 9:
			var lp := _line_pos4(side, i)
			if board[lp.y][lp.x] == null:
				board[lp.y][lp.x] = R.make_piece(side, R.Type.PAWN)
		_show_status4("女祭司:所有兵前进一格,补全兵线")
	_apply_skill_cd4(perk_id, side)
	queue_redraw()
	_consume_turn_after_skill4()


func _skill_fool4(perk_id: String, side: int) -> void:
	if perk_id == "yuzhe2":
		_fool_restore4(side)
	else:
		_fool_shuffle4(side)
	_apply_skill_cd4(perk_id, side)
	selected4 = Vector2i(-1, -1)
	moves4 = []
	queue_redraw()
	_consume_turn_after_skill4()


func _fool_shuffle4(side: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var positions: Array[Vector2i] = []
	var pieces: Array = []
	for r in board.size():
		for c in board[r].size():
			var p = board[r][c]
			if p == null:
				continue
			if p["type"] == R.Type.KING or p["type"] == R.Type.ADVISOR:
				continue
			if rng.randf() < 0.75:
				continue
			positions.append(Vector2i(c, r))
			pieces.append(p)
	pieces.shuffle()
	for i in positions.size():
		var pos: Vector2i = positions[i]
		board[pos.y][pos.x] = pieces[i]
	_show_status4("愚者:棋子位置被打乱,跳过本回合!")


func _fool_restore4(side: int) -> void:
	# 无开局快照:仅提示(四人不做复原,避免破坏四方布局)
	_show_status4("愚者:复原需开局快照,四人模式暂不生效")


func _skill_temperance4(perk_id: String, side: int) -> void:
	if perk_id == "jiezhi2":
		actions_left4 += 1
		skip_next_turn4[side] = true
		_apply_skill_cd4(perk_id, side)
		_show_status4("节制:本回合追加行动,下回合跳过")
		queue_redraw()
		return
	extra_turn4[side] = true
	_apply_skill_cd4(perk_id, side)
	_show_status4("节制:跳过本回合,下回合追加行动")
	_consume_turn_after_skill4()


func _skill_queen4(perk_id: String, side: int) -> void:
	if queen_charge4[side] <= 0:
		_show_status4("[皇后] 充能中:己方每被吃 1 子充能 1 点")
		return
	queen_charge4[side] -= 1
	if perk_id == "huanghou2":
		counter_side4 = side
		_apply_skill_cd4(perk_id, side)
		status_label.text = "皇后:所有棋子获得反制(被吃同归于尽)"
	else:
		invincible_side4 = side
		invincible_side_turns4 = 2
		_show_status4("皇后:己方所有棋子无敌(持续2回合)")
	queue_redraw()
	_consume_turn_after_skill4()


# 恋人(逆位):被吃充能(需求 2),使用后己方其他技能全部完成冷却/充能
func _skill_lianren2_4(side: int) -> void:
	if lianren2_charge4[side] < 2:
		_show_status4("[恋人] 充能中:己方每被吃 1 子充能 1 点(需 2 点)")
		return
	lianren2_charge4[side] -= 2
	# 己方其他主动技能冷却清零
	for id in skill_cd4[side].keys():
		skill_cd4[side][id] = 0
	# 皇后/死亡充能补满(到各自上限;逆位力量可累计至 3 倍)
	var qcap4 := 3 if perks4[side].has("liliang2") else 1
	if perks4[side].has("huanghou") or perks4[side].has("huanghou2"):
		queen_charge4[side] = qcap4
	var scap4 := 9 if perks4[side].has("liliang2") else 3
	if perks4[side].has("siwang") or perks4[side].has("siwang2"):
		siwang_charge4[side] = scap4
	_show_status4("恋人:己方其他技能全部完成冷却/充能")
	_refresh_perk_panels4()
	queue_redraw()
	_consume_turn_after_skill4()


func _skill_wheel4(perk_id: String, side: int) -> void:
	if perk_id == "mingyun2":
		var own: Array[Vector2i] = []
		for r in board.size():
			for c in board[r].size():
				var p = board[r][c]
				if p != null and p["side"] == side and p["type"] != R.Type.KING:
					own.append(Vector2i(c, r))
		if own.size() < 2:
			_show_status4("己方棋子不足,无法协同")
			return
		own.shuffle()
		sync_pieces4 = [own[0], own[1]]
		_apply_skill_cd4(perk_id, side)
		_show_status4("命运之轮:随机两子协同(移动不消耗步数)")
		queue_redraw()
		_update_status4()
		return
	actions_left4 += 1
	_apply_skill_cd4(perk_id, side)
	_show_status4("命运之轮:本回合可额外移动一次")
	queue_redraw()
	_update_status4()


func _skill_hermit4(perk_id: String, side: int) -> void:
	if perk_id == "yinzhe2":
		# 进阶:己方所有子隐身(每回合每子 10% 概率破隐,移动后立刻破隐)
		for r in board.size():
			for c in board[r].size():
				var p = board[r][c]
				if p != null and p["side"] == side and p["type"] != R.Type.KING:
					hidden_pieces4[Vector2i(c, r)] = side + 100
		_apply_skill_cd4(perk_id, side)
		_show_status4("隐者:己方所有子隐身(每回合10%概率破隐,移动即破隐)")
		queue_redraw()
		_consume_turn_after_skill4()
		return
	hermit_pending4 = true
	_apply_skill_cd4(perk_id, side)
	_show_status4("隐者:下回合移动的子隐身一回合")
	queue_redraw()


func _skill_justice2_4(side: int) -> void:
	if perks4[side].has("_cannon_2"):
		perks4[side].erase("_cannon_2")
		_show_status4("正义:炮恢复隔一子吃")
	else:
		perks4[side]["_cannon_2"] = true
		_show_status4("正义:炮变为隔两子吃")
	_apply_skill_cd4("zhengyi2", side)
	queue_redraw()
	_consume_turn_after_skill4()


func _skill_death2_4(side: int) -> void:
	if siwang_charge4[side] <= 0:
		_show_status4("[死亡] 充能中:己方每被吃 1 子充能 1 点")
		return
	siwang_charge4[side] -= 1
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var own: Array[Vector2i] = []
	var enemy: Array[Vector2i] = []
	for r in board.size():
		for c in board[r].size():
			var q = board[r][c]
			if q == null or q["type"] == R.Type.KING:
				continue
			var v := Vector2i(c, r)
			if q["side"] == side:
				own.append(v)
			else:
				enemy.append(v)
	if not own.is_empty():
		var o: Vector2i = own.pick_random()
		if rng.randf() >= 0.5:
			board[o.y][o.x] = null
	if not enemy.is_empty():
		var e: Vector2i = enemy.pick_random()
		board[e.y][e.x] = null
	_apply_skill_cd4("siwang2", side)
	_show_status4("死亡:随机摧毁敌我各一子")
	queue_redraw()
	_consume_turn_after_skill4()
