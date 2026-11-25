#!/bin/bash
# build_snes9x.sh
# 将 Snes9x 编译为 iOS 静态库
# 使用方法：在项目根目录执行 bash RetroEmu/Core/build_snes9x.sh
#
# 前置条件：
#   brew install cmake
#   git submodule add https://github.com/snes9xgit/snes9x.git Snes9x

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SNES9X_DIR="$SCRIPT_DIR/../../Snes9x"
OUTPUT_DIR="$SCRIPT_DIR/../../libs/snes9x"

if [ ! -d "$SNES9X_DIR" ]; then
    echo "❌ Snes9x 源码不存在，请先执行："
    echo "   git submodule add https://github.com/snes9xgit/snes9x.git Snes9x"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# iOS arm64
cmake -S "$SNES9X_DIR" -B "$OUTPUT_DIR/build-arm64" \
    -DCMAKE_TOOLCHAIN_FILE="$SCRIPT_DIR/ios.toolchain.cmake" \
    -DPLATFORM=OS64 \
    -DCMAKE_BUILD_TYPE=Release \
    -DSNES9X_CORE_ONLY=ON \
    -DSNES9X_STATIC=ON

cmake --build "$OUTPUT_DIR/build-arm64" --config Release -j$(sysctl -n hw.ncpu)

cp "$OUTPUT_DIR/build-arm64/libsnes9x.a" "$OUTPUT_DIR/libsnes9x-arm64.a"

echo "✅ Snes9x 静态库已生成：$OUTPUT_DIR/libsnes9x-arm64.a"
echo ""
echo "📋 Xcode 配置步骤："
echo "  1. 将 libsnes9x-arm64.a 拖入 Xcode → Frameworks"
echo "  2. Build Settings → Header Search Paths 添加 Snes9x/ 和 Snes9x/unix/"
echo "  3. Build Settings → Other C++ Flags 添加 -DHAVE_STDINT_H -DUNZIP_SUPPORT"
echo "  4. Build Settings → Other Swift Flags 添加 -D RETRO_NATIVE_CORE"
