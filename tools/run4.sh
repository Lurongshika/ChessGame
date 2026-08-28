#!/bin/bash
# 一键同时启动 4 个进程测试四人模式:
#   主机 + 3 个客户端 → 等候大厅(4 人齐自动开局)
# 用法:
#   bash tools/run4.sh           # GUI 窗口(2x2 排布,可直观观察)
#   bash tools/run4.sh headless  # 无窗口模式(日志在 /tmp/four_*.log)
# 可改 IP 测试局域网真机:IP=192.168.x.x bash tools/run4.sh
set -e
cd "$(dirname "$0")/.."

IP="${IP:-127.0.0.1}"
PORT="${PORT:-7777}"
MODE="${MODE:-headless}"   # gui / headless
[ "$1" = "headless" ] && MODE=headless
LOG=/tmp/four

pkill -9 godot 2>/dev/null || true
sleep 0.5

# 窗口位置(2x2 排布,1280x720)
POS0="--position 0,0"
POS1="--position 1280,0"
POS2="--position 0,720"
POS3="--position 1280,720"
[ "$MODE" = "headless" ] && H="--headless" || H=""

G="godot --path . res://scenes/lobby.tscn -- $H"

# 主机(红方,4 人齐自动开局)
$G --net=host --mode=four --auto-start --auto $POS0 >$LOG-host.log 2>&1 &
echo "host pid=$!"

# 3 个客户端(黑/绿/蓝)
$G --net=client --ip=$IP --mode=four --auto $POS1 >$LOG-c1.log 2>&1 &
echo "client1 pid=$!"
$G --net=client --ip=$IP --mode=four --auto $POS2 >$LOG-c2.log 2>&1 &
echo "client2 pid=$!"
$G --net=client --ip=$IP --mode=four --auto $POS3 >$LOG-c3.log 2>&1 &
echo "client3 pid=$!"

echo "--- 已启动 4 进程,日志: /tmp/four-host.log /tmp/four-c1.log /tmp/four-c2.log /tmp/four-c3.log ---"
echo "--- 全部加入后主机会自动开局;结束时 pkill godot ---"
