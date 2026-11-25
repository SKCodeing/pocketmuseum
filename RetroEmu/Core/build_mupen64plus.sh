#!/bin/bash
# build_mupen64plus.sh
# 将 Mupen64Plus-Core 编译为 iOS 静态库（解释器模式，无 JIT）
# 使用方法：bash RetroEmu/Core/build_mupen64plus.sh
#
# 前置条件：
#   brew install cmake
#   git submodule add https://github.com/mupen64plus/mupen64plus-core.git mupen64plus-core

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
M64_DIR="$SCRIPT_DIR/../../mupen64plus-core"
OUTPUT_DIR="$SCRIPT_DIR/../../libs/mupen64plus"

if [ ! -d "$M64_DIR" ]; then
    echo "❌ mupen64plus-core 源码不存在，请先执行："
    echo "   git submodule add https://github.com/mupen64plus/mupen64plus-core.git mupen64plus-core"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

cmake -S "$M64_DIR" -B "$OUTPUT_DIR/build-arm64" \
    -DCMAKE_TOOLCHAIN_FILE="$SCRIPT_DIR/ios.toolchain.cmake" \
    -DPLATFORM=OS64 \
    -DCMAKE_BUILD_TYPE=Release \
    -DUSE_DYNAREC=OFF \
    -DUSE_INTERPRETER=ON \
    -DBUILD_SHARED_LIBS=OFF

cmake --build "$OUTPUT_DIR/build-arm64" --config Release -j$(sysctl -n hw.ncpu)

echo "✅ Mupen64Plus 静态库已生成"
echo ""
echo "📋 Xcode 配置步骤："
echo "  1. 将 libmupen64plus.a 拖入 Xcode → Frameworks"
echo "  2. Build Settings → Header Search Paths 添加 mupen64plus-core/src/api/"
echo "  3. Build Settings → Other Swift Flags 添加 -D RETRO_NATIVE_CORE"
echo ""
echo "⚠️  注意：解释器模式性能约为 JIT 的 1/5，建议 iPhone 13+ 使用"
