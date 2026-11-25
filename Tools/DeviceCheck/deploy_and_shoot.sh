#!/bin/bash
# deploy_and_shoot.sh
# 真机部署 + UI 巡检截图一条龙。
#
# 用法：
#   ./Tools/DeviceCheck/deploy_and_shoot.sh              # 自动挑选已连接设备
#   ./Tools/DeviceCheck/deploy_and_shoot.sh <设备UDID>    # 指定设备
#   ./Tools/DeviceCheck/deploy_and_shoot.sh <UDID> --no-build   # 复用上次构建产物
#
# 产物：AppStore/screenshots-iphone/<页面名>.png
#
# 说明：
# - 必须用 ENABLE_DEBUG_DYLIB=NO / ENABLE_PREVIEWS=NO，否则 bundle 会变成
#   stub + debug dylib 形态，devicectl 会判定「not a valid bundle」。
# - 覆盖安装偶发 3002/3000 报错，脚本先 uninstall 再 install。
# - 首次安装后 devicectl 的容器路径缓存可能过期，拉取失败时自动重试。

set -u

cd "$(dirname "$0")/../.." || exit 1

BUNDLE_ID="com.haoheng.RetroEmu"
DD_PATH=".tmp/dd-device"
APP_PATH="$DD_PATH/Build/Products/Debug-iphoneos/RetroEmu.app"
OUT_DIR="AppStore/screenshots-iphone"
SHOTS=(01-home 02-timeline 03-settings 04-library)

DEVICE="${1:-}"
if [ "${2:-}" = "--no-build" ]; then
    SKIP_BUILD=1
else
    SKIP_BUILD=0
fi

if [ -z "$DEVICE" ]; then
    DEVICE=$(xcrun devicectl list devices 2>/dev/null | awk '/connected/ {print $3; exit}')
    if [ -z "$DEVICE" ]; then
        echo "✗ 没有找到已连接的真机，请先用数据线连接并信任此电脑"
        exit 1
    fi
fi

echo "▸ 设备：$DEVICE"

if [ "$SKIP_BUILD" -eq 0 ]; then
    echo "▸ 构建 Debug（关闭 debug dylib / preview）"
    xcodebuild -scheme RetroEmu -configuration Debug \
        -destination "id=$DEVICE" \
        -derivedDataPath "$DD_PATH" \
        -allowProvisioningUpdates \
        ENABLE_DEBUG_DYLIB=NO ENABLE_PREVIEWS=NO \
        build > .tmp/deploy_build.log 2>&1

    if ! grep -q "BUILD SUCCEEDED" .tmp/deploy_build.log; then
        echo "✗ 构建失败，详见 .tmp/deploy_build.log"
        grep -E "error:" .tmp/deploy_build.log | head -10
        exit 1
    fi
fi

echo "▸ 安装到设备"
xcrun devicectl device uninstall app --device "$DEVICE" "$BUNDLE_ID" > /dev/null 2>&1
sleep 2
INSTALLED=0
for _ in 1 2 3; do
    if xcrun devicectl device install app --device "$DEVICE" "$APP_PATH" 2>&1 | grep -q "App installed"; then
        INSTALLED=1
        break
    fi
    sleep 3
done
if [ "$INSTALLED" -eq 0 ]; then
    echo "✗ 安装失败，可尝试拔线重连或重启设备后再跑一次"
    exit 1
fi

echo "▸ 启动并逐页截图"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" -- -skipIntro -captureShots 2>&1 | tail -1

# 等 4 个页面切换 + 落盘
sleep 18

mkdir -p "$OUT_DIR"
FAILED=0
for shot in "${SHOTS[@]}"; do
    ok=0
    for _ in 1 2 3 4; do
        if xcrun devicectl device copy from --device "$DEVICE" \
            --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
            --source "Documents/Shots/$shot.png" \
            --destination "$(pwd)/$OUT_DIR/$shot.png" 2>&1 | grep -q "File received"; then
            ok=1
            break
        fi
        sleep 2
    done
    if [ "$ok" -eq 1 ]; then
        echo "  ✓ $shot.png"
    else
        echo "  ✗ $shot.png 拉取失败"
        FAILED=1
    fi
done

if [ "$FAILED" -eq 1 ]; then
    exit 1
fi
echo "▸ 完成：$OUT_DIR"
