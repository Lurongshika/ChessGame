# 秘弈 (skill_chess)

技能型中国象棋,Godot 4.7(GDScript)。双人/四人、本地/联机、技能与塔罗卡牌。

**当前版本: v1.7**(主界面左下角版本按钮可查看更新概览)。

## 运行 / 导出

```bash
# 运行
godot --path .
# 冒烟(无头)
godot --headless --path . res://scenes/game.tscn --quit-after 60
godot --headless --path . res://scenes/game.tscn --quit-after 60 -- --mode=four
# 导出(预设见 export_presets.cfg,产物在 build/ 已被 git 忽略)
godot --headless --path . --export-release "macOS" build/skill_chess_mac.zip
godot --headless --path . --export-release "Windows Desktop" build/skill_chess_windows.exe
```

## 目录要点

| 路径 | 说明 |
|---|---|
| `global.gd`(autoload) | 全局状态:game_mode/net_role/player_colors/lobby_players/spectators/game_rules(自定义规则)/crt 设置;`_parse_cmdline_args` 解析 CLI |
| `scripts/chess_rules.gd` | 规则引擎(静态):2p 数组棋盘 + 4p 17×17;`raw_moves`/`legal_moves`/`is_in_check`/`apply_move`;**帅将不能面对面**在 `is_in_check`;兵过河判定 4p 用 `in_arm4`、2p 用行列 |
| `scripts/perks.gd` | 44 技能数据(id/name/tip/desc/cat)与抽牌 `draw_options` |
| `scripts/game.gd` | 对局主逻辑(~8000 行):双人/四人、技能执行、选牌(8选3+技能数量+重抽)、联机状态同步、观战、AI 接入 |
| `scripts/ai.gd` | 搜索型 AI:negamax alpha-beta + quiescence + Zobrist TT + 历史启发式 + 位置表估值;时间受限(depth2 为主) |
| `scripts/lobby.gd` | 等候大厅:玩家/观战席、自定义选项、开局 RPC |
| `scripts/custom_options.gd` | 自定义规则面板:win_mode/kill_count/king_down/promotion/**skill_count(1-4)/reroll(选牌重置开关)** |
| `scripts/main_menu.gd` | 主菜单;**v1.7 版本按钮 + 更新概览** |
| `scripts/tarot.gd` / `perk_card.gd` / `tarot_tooltip.gd` | 塔罗卡牌映射、技能卡控件(3D倾斜/选中/悬浮提示)、跟随鼠标解释框(卡牌+棋子坐标/状态) |
| `scripts/manual.gd` | 技能图鉴 |
| `shaders/card_3d.gdshader` 等 | 卡牌 3D/飞行动画 shader |

## 核心机制

- **技能**:44 个;主动技能分目标型(魔术师/皇帝/死亡/隐者等,选目标)→ 主机权威执行;被动技能每回合自动生效。
- **死亡状态**:被死亡技能标记的棋子到期自动摧毁、移动解毒;死亡逆位=下回合移动的非己方子中毒。
- **同一子每回合一次**:普通落子(正式移动)每子每回合一次;星星逆位免费移兵可用蓄势连续动同一兵。
- **选牌(8选3)**:技能数量 1-4(默认3);`reroll` 开启时显示"重置(未选重抽)",已选保留、未选重抽。
- **联机**:主机权威;客户端发请求(`request_move/request_skill4`),主机执行后 `_broadcast_state(_4)` 广播;**观战席**不占席位、禁操作、收状态。
- **帅将不能面对面**:双方将帅同列且无子相隔 → 被将;移开隔子致见面 = 非法走法。
- **自定义规则** 存 `Global.game_rules`(随自定义选项保存/下发)。

## 调试指令(游戏内聊天)

```
/place x y 类型|null     放置/摧毁棋子
/skill 方 id on|off       增删技能
/charge 方 id 值          设置充能(huanghou/huanghou2/siwang/siwang2/xingxing2)
/state 方 无敌|反制 | /state x y 隐身|显形
/skip                    跳过当前回合
```

## 命令行参数(自动化/联机测试)

```
--demo=<技能id>    图鉴演示对局(红方拥有该技能)
--mode=four        四人模式
--mode=pvp|ai      双人联机/人机
--net=host|client --ip=127.0.0.1 --port=<端口>   联机
--auto             自动测试入口(按 net_role 直接进对局)
--auto-start       大厅:有玩家即自动开局(可配 skill_count/reroll)
```

本地多端联机测试(同机开多进程):

```bash
godot --headless --path . res://scenes/lobby.tscn -- --net=host --port=7100 --mode=pvp > /tmp/host.log 2>&1 &
godot --headless --path . res://scenes/lobby.tscn -- --net=client --ip=127.0.0.1 --port=7100 --mode=pvp > /tmp/c1.log 2>&1 &
godot --headless --path . res://scenes/lobby.tscn -- --net=client --ip=127.0.0.1 --port=7100 --mode=pvp > /tmp/c2.log 2>&1 &
# 检查 /tmp/host.log:第3个客户端在席位满时自动转观战(spectators)
```

## 测试

```bash
godot --headless --path . --script res://tests/test_tarot.gd        # 塔罗映射
godot --headless --path . --script res://tests/test_game_flow.gd    # 双人对局流程
godot --headless --path . --script res://tests/test_four_skills.gd  # 四人技能
```

## 版本历史(概要)

- **v1.7**:过河兵横走修复(4p 红/黑);帅将不能面对面;技能数量(1-4)+选牌重置;观战席;坐标对局记录;死亡中毒;AI 增强;版本按钮。
- **v1.6**:塔罗卡牌技能、死亡状态等。
- **v1.5**:技能卡展示与选牌界面。

## 常见坑 / 约定

- GDScript:`var x := dict[k]` 推断失败(Variant)→ 用显式类型;`Vector2(0.5)` 非法(用 `Vector2(0.5,0.5)`);信号回调参数个数必须匹配。
- 联机每回合追踪(`_turn_moved/_controlled_moved/_sync_moved`)在 `_apply_state_data(_4)` 重置(客户端以主机为准),新增"每回合一次"类状态记得同步。
- 规则引擎对 2p(10×9)与 4p(17×17)共用;4p 的过河/九宫/方向用 `in_arm4`/`ARMS4`,判棋盘尺寸 `board.size()==17`。
- 加"每回合/持续 N 回合"效果:按"自己结束回回到自己下次结束回合"计,`_tick_poison` 在回合结束递减。
- 导出前:先跑冒烟 + `test_tarot`/`test_game_flow`/`test_four_skills`;`git add -A` 提交推 `origin main`。
