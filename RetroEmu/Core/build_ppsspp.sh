#!/bin/bash
# build_ppsspp.sh
# 将 PPSSPP Core 编译为 iOS 静态库（IR Interpreter 模式，App Store 合规）
# 使用方法：bash RetroEmu/Core/build_ppsspp.sh
#
# 前置条件：
#   brew install cmake python3
#   git submodule add https://github.com/hrydgard/ppsspp.git ppsspp
#   cd ppsspp && git submodule update --init --recursive

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PPSSPP_DIR="$SCRIPT_DIR/../../ppsspp"
OUTPUT_DIR="$SCRIPT_DIR/../../libs/ppsspp"
MODE="${1:-interpreter}"  # interpreter | jit

if [ ! -d "$PPSSPP_DIR" ]; then
    echo "❌ PPSSPP 源码不存在，请先执行："
    echo "   git submodule add https://github.com/hrydgard/ppsspp.git ppsspp"
    echo "   cd ppsspp && git submodule update --init --recursive"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

if [ "$MODE" = "jit" ]; then
    echo "⚡ 构建 JIT 模式（仅用于旁加载/开发，不可上架 App Store）"
    JIT_FLAGS="-DUSE_ARMJIT=ON -DIOS_JIT=ON"
    BUILD_DIR="$OUTPUT_DIR/build-arm64-jit"
    LIB_SUFFIX="-jit"
else
    echo "🛡️  构建 IR Interpreter 模式（App Store 合规）"
    JIT_FLAGS="-DUSE_ARMJIT=OFF -DIOS_JIT=OFF"
    BUILD_DIR="$OUTPUT_DIR/build-arm64"
    LIB_SUFFIX=""
fi

cmake -S "$PPSSPP_DIR" -B "$BUILD_DIR" \
    -DCMAKE_TOOLCHAIN_FILE="$SCRIPT_DIR/ios.toolchain.cmake" \
    -DPLATFORM=OS64 \
    -DCMAKE_BUILD_TYPE=Release \
    -DIOS=ON \
    -DUSING_GLES2=ON \
    -DUSING_EGL=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DHEADLESS=OFF \
    -DUNITTEST=OFF \
    -DSIMULATOR=OFF \
    $JIT_FLAGS

cmake --build "$BUILD_DIR" --config Release -j$(sysctl -n hw.ncpu)

# 复制产物
cp "$BUILD_DIR/lib/libPPSSPPCore.a" "$OUTPUT_DIR/libPPSSPPCore${LIB_SUFFIX}-arm64.a"

echo ""
echo "✅ PPSSPP Core 静态库已生成：$OUTPUT_DIR/libPPSSPPCore${LIB_SUFFIX}-arm64.a"
echo ""
echo "📋 Xcode 配置步骤："
echo "  1. 将 libPPSSPPCore${LIB_SUFFIX}-arm64.a 拖入 Xcode → Frameworks"
echo "  2. Build Settings → Header Search Paths 添加："
echo "     ppsspp/"
echo "     ppsspp/Core/"
echo "     ppsspp/Common/"
echo "     ppsspp/ext/glslang/"
echo "  3. Build Settings → Other C++ Flags 添加 -std=c++17"
if [ "$MODE" = "jit" ]; then
    echo "  4. Build Settings → Other Swift Flags 添加 -D RETRO_NATIVE_CORE -D PSP_JIT_ENABLED"
    echo ""
    echo "⚠️  JIT 模式注意事项："
    echo "  - 需要在 Entitlements 添加 com.apple.security.cs.allow-jit = true"
    echo "  - 此权限需要 Apple 审批，普通 App Store 提交会被拒绝"
    echo "  - 仅适用于：旁加载 / AltStore / 企业证书 / EU 地区特殊权限"
else
    echo "  4. Build Settings → Other Swift Flags 添加 -D RETRO_NATIVE_CORE"
    echo ""
    echo "ℹ️  IR Interpreter 模式性能说明："
    echo "  - iPhone 12+ (A14): 大多数游戏全速运行"
    echo "  - iPhone 11 (A13): 约 85-90% 速度"
    echo "  - iPhone X 及以下: 部分游戏可能卡顿"
fi
