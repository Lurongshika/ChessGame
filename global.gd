extends Node

# 全局单例:记录对战模式与联机参数
var game_mode := "pvp"      # "pvp" 双人 / "ai" 人机(本地)
var net_role := "local"     # "local" 本地 / "host" 联机主机(红方) / "client" 联机客户端(黑方)
var server_ip := ""         # 联机客户端:目标主机 IP
var port := 7777            # 联机端口(内网穿透时按穿透配置修改)
var load_slot := 0          # 主菜单「选择存档」:进入游戏场景后加载指定槽位(0=不加载)
var standard_mode := false  # 标准模式:双方不使用任何技能
var perk_pool := "all"      # 技能池:all(44 个,正位+逆位)
var demo_perk := ""         # 技能图鉴:当前演示的技能 id(非空时进入演示对局)
var my_color := -1          # 大厅:己方选的棋子颜色索引(0-15)
var player_colors := {}     # 对局:side -> 棋子颜色索引(大厅分配)
var lobby_players := {}     # 对局:side -> {name, avatar_data, color} 四方玩家信息(大厅传入)
var from_lobby := false     # 是否从等候大厅进入对局(复用大厅连接)

# 16 种棋子颜色预设(大厅选色板与对局棋子共用)
# 12 种颜色:去掉接近棋盘木色(黄/棕)/黑方棋子/白底的颜色,保证辨识度
const COLORS16 := [
	Color(0.75, 0.15, 0.12), Color(0.1, 0.35, 0.75), Color(0.1, 0.6, 0.2),
	Color(0.6, 0.2, 0.7), Color(0.95, 0.3, 0.6), Color(0.1, 0.8, 0.85),
	Color(0.5, 0.5, 0.5), Color(0.95, 0.3, 0.2), Color(0.2, 0.3, 0.8),
	Color(0.4, 0.9, 0.5), Color(0.9, 0.2, 0.4), Color(0.95, 0.6, 0.1),
]


func _ready() -> void:
	# 支持命令行参数启动(用于自动化测试):--net=host/client --ip=192.168.x.x --port=7777 --mode=pvp/ai --slot=1 --pool=normal/advanced
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--net="):
			net_role = arg.trim_prefix("--net=")
		elif arg.begins_with("--ip="):
			server_ip = arg.trim_prefix("--ip=")
		elif arg.begins_with("--port="):
			var p := int(arg.trim_prefix("--port="))
			if p > 0:
				port = p
		elif arg.begins_with("--mode="):
			game_mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--pool="):
			perk_pool = arg.trim_prefix("--pool=")
		elif arg.begins_with("--slot="):
			load_slot = int(arg.trim_prefix("--slot="))
	# 客户端未指定 IP 时默认本机回环(本机双开联机测试)
	if net_role == "client" and server_ip.is_empty():
		server_ip = "127.0.0.1"
