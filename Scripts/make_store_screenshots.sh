#!/usr/bin/env bash
# 生成 App Store 审核用截图：六张叙事序列（首页→展签→时光轴→年度回顾→游戏内→设置）。
#
# 用法：Scripts/make_store_screenshots.sh <模拟器 UDID> <输出目录> [显示端口]
#   iPhone 6.3"（1206×2622）  UDID 用 ASC 槽位对应的 iPhone
#   13"  iPad  （2064×2752）  UDID 用 ASC iPad 13
#   iPhone Duo （1398×2034）  UDID 用 ASC iPhone Duo，默认抓折叠态外屏
#   iPhone Duo 展开态（2853×2007）同上，第三个参数传 3（内屏为 display 3）
#       展开/折叠是 DeviceHub 里的交互状态，命令行改不了：headless 启动固定回折叠态，
#       抓内屏前先手动展开；抓完想回折叠态就 shutdown + boot
#
# 宽屏版式：内容列宽 ≥900pt 时自动收成 860pt 居中阅读栏（iPad 竖屏 1032pt、Duo 内屏 951pt），
# 卡带列表改两列；iPhone 窄屏内边距为 0，抓图尺寸与版式都不变。
#
# 为什么不用应用内 render：ASC 对每种尺寸只认设备原始像素，应用内画出来的
# 是 window bounds，尺寸对不上。这里用 simctl 原分辨率截图，App 只负责把页面切到位。

set -euo pipefail

UDID="${1:?用法: make_store_screenshots.sh <UDID> <输出目录> [显示端口]}"
OUT="${2:?用法: make_store_screenshots.sh <UDID> <输出目录> [显示端口]}"
# Duo 这类多显示屏设备：1 是折叠态外屏（1398×2034），3 是展开态内屏（2853×2007）。
# 单屏设备带 --display=1 也能正常工作。
DISPLAY="${3:-1}"
BUNDLE="com.haoheng.RetroEmu"

cd "$(dirname "$0")/.."
mkdir -p "$OUT"

doc_dir() {
    xcrun simctl get_app_container "$UDID" "$BUNDLE" data
}

shots_dir() {
    echo "$(doc_dir)/Documents/Shots"
}

wait_marker() {
    local marker="$1" timeout="${2:-40}" i=0
    while [ "$i" -lt "$timeout" ]; do
        if [ -f "$(shots_dir)/$marker" ]; then return 0; fi
        sleep 0.5
        i=$((i + 1))
    done
    echo "等待 $(shots_dir)/$marker 超时" >&2
    return 1
}

clear_marker() {
    rm -f "$(shots_dir)/$1"
}

app_stop() {
    xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
    # terminate 是异步的：进程还没退干净时再 launch 会直接复用旧实例（新参数不生效），
    # 后面的 READY 标记就要白等到超时。这里给它一点落地时间。
    sleep 2
}

# 启动 App 并等待 READY 标记。进程残留时 launch 会复用旧实例，参数被忽略，
# 所以超时后强杀重试一次，不让单次卡住整轮截图。
launch_and_wait() {
    local marker="$1"
    shift
    xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
    wait_marker "$marker" 60 && return 0
    echo "  未等到 $marker，重启 App 再试一次" >&2
    app_stop
    xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
    wait_marker "$marker" 60
}

# Duo 这类多显示屏设备必须指明 --display（外屏 1 / 内屏 3）。
# 不指定的话 simctl 在部分状态下会报 Invalid argument 而拿不到图。
#
# 先 rm -f 再截：直接覆盖已存在的旧截图，simctl 会报
# 「You don't have permission to save the file ...」(NSCocoaErrorDomain 513)，
# 删掉目标文件后重新写入就正常。
shot() {
    local path="$1"
    rm -f "$path"
    xcrun simctl io "$UDID" screenshot --display="$DISPLAY" "$path" >/dev/null 2>&1 || {
        rm -f "$path"
        xcrun simctl io "$UDID" screenshot "$path" >/dev/null
    }
}

# 先跑一次空启动：把内置演示卡带 seed 进 Documents（首次安装才会做）
seed_demo_cartridge() {
    app_stop
    xcrun simctl launch "$UDID" "$BUNDLE" -skipIntro >/dev/null
    sleep 6
    app_stop
}

# 造几条真实存档，别让「时光」页和首页「最近上手」空着
seed_history() {
    app_stop
    clear_marker HISTORY_READY.txt
    launch_and_wait HISTORY_READY.txt -skipIntro -makeHistory
    app_stop
}

# 统计数字用固定的一套，截图之间不会因为多玩了几秒而变化（3h 57m 等）
seed_stats() {
    app_stop
    xcrun simctl launch "$UDID" "$BUNDLE" -seedStats >/dev/null
    sleep 3
    app_stop
}

# 切到某一页并原分辨率截图
capture_page() {
    local page="$1" name="$2"
    app_stop
    clear_marker PAGE_READY.txt
    launch_and_wait PAGE_READY.txt -skipIntro -shotPage "$page"
    sleep 0.6
    shot "$OUT/$name.png"
    echo "  ✔ $name.png"
    app_stop
}

# 游戏内：进第一张卡带、补一次 START，暂停定格后再截图
capture_gameplay() {
    local name="$1"
    app_stop
    clear_marker GAME_READY.txt
    launch_and_wait GAME_READY.txt -skipIntro -openROM -autoStart
    sleep 0.6
    shot "$OUT/$name.png"
    echo "  ✔ $name.png"
    app_stop
}

echo "== 准备数据 =="
seed_demo_cartridge
seed_history
seed_stats

# 状态栏统一成满电满格；时间取当前时间，跟「时光」页里的存档时刻对得上，
# 避免出现 9:41 的状态栏配 16:04 的存档记录那种自相矛盾
xcrun simctl status_bar "$UDID" override \
    --time "$(date +%-H:%M)" --batteryState charged --batteryLevel 100 \
    --wifiBars 3 --cellularBars 4 >/dev/null 2>&1 || true

echo "== 抓图 =="
capture_page home     01-home
capture_page exhibit  02-exhibit
capture_page timeline 03-timeline
capture_page report   04-report
capture_gameplay      05-gameplay
capture_page settings 06-settings

echo "== 完成，产物在 $OUT =="
