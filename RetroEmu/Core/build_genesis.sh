#!/bin/bash
# build_genesis.sh
# 将 Genesis-Plus-GX core 编译为静态库 libgenesis.a

set -e

SRCROOT="${SRCROOT}"
GX_CORE="${SRCROOT}/GenesisPlus/core"
BRIDGE_DIR="${SRCROOT}/RetroEmu/Core/Bridge"
OUTPUT_DIR="${BUILT_PRODUCTS_DIR}"
LIB_OUT="${OUTPUT_DIR}/libgenesis.a"
# obj 目录包含平台信息，避免真机/模拟器缓存互相污染
OBJ_DIR="${DERIVED_FILE_DIR}/genesis_objs_${PLATFORM_NAME}"

# 如果静态库已存在且比源码新，跳过
if [ -f "${LIB_OUT}" ]; then
    NEWEST_SRC=$(find "${GX_CORE}" -name "*.c" -newer "${LIB_OUT}" | head -1)
    if [ -z "${NEWEST_SRC}" ]; then
        echo "libgenesis.a is up to date, skipping."
        exit 0
    fi
fi

mkdir -p "${OBJ_DIR}"

# 根据平台选择正确的 target triple，避免模拟器/真机架构标签不匹配
if [[ "${PLATFORM_NAME}" == *"simulator"* ]]; then
    # 模拟器：使用 -target 明确指定 simulator 环境
    PLATFORM_FLAGS="-target ${ARCHS}-apple-ios${IPHONEOS_DEPLOYMENT_TARGET}-simulator"
else
    # 真机：使用传统 flag
    PLATFORM_FLAGS="-arch ${ARCHS} -miphoneos-version-min=${IPHONEOS_DEPLOYMENT_TARGET}"
fi

# 排除不需要的文件（libchdr 依赖太多，CD 音频用不到）
EXCLUDE_PATTERNS=(
    "libchdr"
    "minimp3"
    "tremor"
)

OBJ_FILES=()

# 编译 core/ 下所有 .c 文件
while IFS= read -r -d '' C_FILE; do
    # 检查是否在排除列表中
    SKIP=0
    for pat in "${EXCLUDE_PATTERNS[@]}"; do
        if [[ "${C_FILE}" == *"${pat}"* ]]; then
            SKIP=1
            break
        fi
    done
    [ $SKIP -eq 1 ] && continue

    BASENAME=$(basename "${C_FILE}" .c)
    # 避免同名文件冲突，用相对路径生成唯一 obj 名
    REL_PATH="${C_FILE#${GX_CORE}/}"
    OBJ_NAME=$(echo "${REL_PATH}" | tr '/' '_' | sed 's/\.c$//')
    OBJ_FILE="${OBJ_DIR}/${OBJ_NAME}.o"
    OBJ_FILES+=("${OBJ_FILE}")

    if [ ! -f "${OBJ_FILE}" ] || [ "${C_FILE}" -nt "${OBJ_FILE}" ]; then
        echo "Compiling: ${REL_PATH}"
        clang \
            -std=c11 \
            -O2 \
            -DLSB_FIRST \
            -DMAX_ROMSIZE=10485760 \
            -DHAVE_NO_SPRITE_LIMIT \
            -DUSE_32BPP_RENDERING \
            -Wno-everything \
            -include stdbool.h \
            -I"${BRIDGE_DIR}" \
            -I"${GX_CORE}" \
            -I"${GX_CORE}/sound" \
            -I"${GX_CORE}/ntsc" \
            -I"${GX_CORE}/z80" \
            -I"${GX_CORE}/m68k" \
            -I"${GX_CORE}/input_hw" \
            -I"${GX_CORE}/cart_hw" \
            -I"${GX_CORE}/cart_hw/svp" \
            -I"${GX_CORE}/cd_hw" \
            -I"${GX_CORE}/debug" \
            ${PLATFORM_FLAGS} \
            -isysroot "${SDKROOT}" \
            -c "${C_FILE}" \
            -o "${OBJ_FILE}" 2>/dev/null || {
            echo "Warning: failed to compile ${REL_PATH}"
            rm -f "${OBJ_FILE}"
            OBJ_FILES=("${OBJ_FILES[@]/${OBJ_FILE}/}")
        }
    fi
done < <(find "${GX_CORE}" -name "*.c" -print0)

# 过滤掉空字符串和不存在的文件
VALID_OBJS=()
for obj in "${OBJ_FILES[@]}"; do
    [ -n "$obj" ] && [ -f "$obj" ] && VALID_OBJS+=("$obj")
done

if [ ${#VALID_OBJS[@]} -eq 0 ]; then
    echo "Error: no object files compiled successfully"
    exit 1
fi

echo "Archiving libgenesis.a (${#VALID_OBJS[@]} objects)..."
ar rcs "${LIB_OUT}" "${VALID_OBJS[@]}"
echo "Built: ${LIB_OUT}"
