#!/bin/bash
# build_melonds.sh
# 将 melonDS 编译为 iOS 静态库
# 使用方法：在项目根目录执行 bash RetroEmu/Core/build_melonds.sh
#
# 前置条件：
#   brew install cmake
#   git submodule add https://github.com/melonDS-emu/melonDS.git melonDS

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MELON_DIR="$SCRIPT_DIR/../../melonDS"
OUTPUT_DIR="$SCRIPT_DIR/../../libs/melonds"

if [ ! -d "$MELON_DIR" ]; then
    echo "❌ melonDS 源码不存在，请先执行："
    echo "   git submodule add https://github.com/melonDS-emu/melonDS.git melonDS"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# iOS arm64（melonDS 需要 C++17）
cmake -S "$MELON_DIR" -B "$OUTPUT_DIR/build-arm64" \
    -DCMAKE_TOOLCHAIN_FILE="$SCRIPT_DIR/ios.toolchain.cmake" \
    -DPLATFORM=OS64 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_STANDARD=17 \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_OGLRENDERER=OFF \
    -DENABLE_JIT=OFF \
    -DENABLE_WIFI=OFF \
    -DENABLE_GDBSTUB=OFF

cmake --build "$OUTPUT_DIR/build-arm64" --config Release -j$(sysctl -n hw.ncpu)

cp "$OUTPUT_DIR/build-arm64/libmelonDS.a" "$OUTPUT_DIR/libmelonDS-arm64.a"

echo "✅ melonDS 静态库已生成：$OUTPUT_DIR/libmelonDS-arm64.a"
echo ""
echo "📋 Xcode 配置步骤："
echo "  1. 将 libmelonDS-arm64.a 拖入 Xcode → Frameworks"
echo "  2. Build Settings → Header Search Paths 添加 melonDS/src/"
echo "  3. Build Settings → Other C++ Flags 添加 -std=c++17"
echo "  4. Build Settings → Other Swift Flags 添加 -D RETRO_NATIVE_CORE"
echo ""
echo "⚠️  注意：NDS 模拟需要 ARM7/ARM9 BIOS 文件（bios7.bin, bios9.bin, firmware.bin）"
echo "   将这些文件放入 App Documents 目录，melonDS 会自动读取"
