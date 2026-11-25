#!/bin/bash
# build_pcsx.sh
# 将 PCSX-ReARMed 编译为 iOS 静态库
# 使用方法：bash RetroEmu/Core/build_pcsx.sh
#
# 前置条件：
#   brew install cmake
#   git submodule add https://github.com/notaz/pcsx_rearmed.git pcsx_rearmed

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PCSX_DIR="$SCRIPT_DIR/../../pcsx_rearmed"
OUTPUT_DIR="$SCRIPT_DIR/../../libs/pcsx"

if [ ! -d "$PCSX_DIR" ]; then
    echo "❌ pcsx_rearmed 源码不存在，请先执行："
    echo "   git submodule add https://github.com/notaz/pcsx_rearmed.git pcsx_rearmed"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

cmake -S "$PCSX_DIR" -B "$OUTPUT_DIR/build-arm64" \
    -DCMAKE_TOOLCHAIN_FILE="$SCRIPT_DIR/ios.toolchain.cmake" \
    -DPLATFORM=OS64 \
    -DCMAKE_BUILD_TYPE=Release \
    -DDYNAREC=OFF \
    -DBUILD_SHARED_LIBS=OFF

cmake --build "$OUTPUT_DIR/build-arm64" --config Release -j$(sysctl -n hw.ncpu)

echo "✅ PCSX-ReARMed 静态库已生成"
echo ""
echo "📋 Xcode 配置步骤："
echo "  1. 将 libpcsx_rearmed.a 拖入 Xcode → Frameworks"
echo "  2. Build Settings → Header Search Paths 添加 pcsx_rearmed/"
echo "  3. Build Settings → Other Swift Flags 添加 -D RETRO_NATIVE_CORE"
echo ""
echo "⚠️  注意：需要 PS1 BIOS 文件（SCPH1001.BIN）"
echo "   将 BIOS 文件放入 App Documents/BIOS/ 目录"
echo "   推荐设备：iPhone 12+"
