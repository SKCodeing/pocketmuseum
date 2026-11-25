#!/bin/bash
# build_mgba.sh
# 将 mGBA 核心编译为静态库 libmgba.a

set -e

SRCROOT="${SRCROOT}"
MGBA="${SRCROOT}/mGBA"
OUTPUT_DIR="${BUILT_PRODUCTS_DIR}"
LIB_OUT="${OUTPUT_DIR}/libmgba.a"
OBJ_DIR="${DERIVED_FILE_DIR}/mgba_objs_${PLATFORM_NAME}"

# 如果静态库已存在且比源码新，跳过
if [ -f "${LIB_OUT}" ]; then
    NEWEST=$(find "${MGBA}/src" -name "*.c" -newer "${LIB_OUT}" | head -1)
    if [ -z "${NEWEST}" ]; then
        echo "libmgba.a is up to date, skipping."
        exit 0
    fi
fi

mkdir -p "${OBJ_DIR}"

# 根据平台选择正确的 target triple，避免模拟器/真机架构标签不匹配
if [[ "${PLATFORM_NAME}" == *"simulator"* ]]; then
    PLATFORM_FLAGS="-target ${ARCHS}-apple-ios${IPHONEOS_DEPLOYMENT_TARGET}-simulator"
else
    PLATFORM_FLAGS="-arch ${ARCHS} -miphoneos-version-min=${IPHONEOS_DEPLOYMENT_TARGET}"
fi

INCLUDES="\
    -I${MGBA}/include \
    -I${MGBA}/src"

CFLAGS="\
    -std=c11 \
    -O2 \
    -DMINIMAL_CORE=2 \
    -DDISABLE_THREADING \
    -DMGBA_STANDALONE \
    -DCOLOR_32_BIT \
    -DENABLE_VFS \
    -DENABLE_VFS_FD \
    -DHAVE_LOCALE \
    -DHAVE_STRLCPY \
    -DHAVE_STRDUP \
    -DHAVE_STRNDUP \
    -Wno-everything \
    ${PLATFORM_FLAGS} \
    -isysroot ${SDKROOT}"

# 需要编译的文件列表（排除 platform、debugger、script、test、tools）
# 动态扫描所有需要的 C 文件（排除 platform、debugger、script、test、tools）
C_FILES=()
while IFS= read -r -d '' f; do
    case "$f" in
        */platform/*|*/debugger/*|*/script/*|*/test/*|*/tools/*) continue ;;
        */gui.c|*/vfs-zip.c|*/vfs-dirent.c|*/vfs-file.c|*/vfs-lzma.c) continue ;;
        */third-party/zlib/*) continue ;;
    esac
    C_FILES+=("$f")
done < <(find "${MGBA}/src" -name "*.c" -print0 | sort -z)

OBJ_FILES=()

for C_FILE in "${C_FILES[@]}"; do
    [ -f "${C_FILE}" ] || { echo "Skip (not found): ${C_FILE}"; continue; }
    REL="${C_FILE#${MGBA}/src/}"
    OBJ_NAME=$(echo "${REL}" | tr '/' '_' | sed 's/\.c$//')
    OBJ_FILE="${OBJ_DIR}/${OBJ_NAME}.o"
    OBJ_FILES+=("${OBJ_FILE}")

    # config.c 用 -O0 避免超时
    FILE_CFLAGS="${CFLAGS}"
    if [[ "${C_FILE}" == *"config.c" ]]; then
        FILE_CFLAGS="${CFLAGS/-O2/-O0}"
    fi

    if [ ! -f "${OBJ_FILE}" ] || [ "${C_FILE}" -nt "${OBJ_FILE}" ]; then
        echo "Compiling: ${REL}"
        clang ${FILE_CFLAGS} ${INCLUDES} -c "${C_FILE}" -o "${OBJ_FILE}" 2>/dev/null || {
            echo "Warning: failed ${REL}"
            rm -f "${OBJ_FILE}"
            OBJ_FILES=("${OBJ_FILES[@]/${OBJ_FILE}/}")
        }
    fi
done

# 编译 version stub
VERSION_OBJ="${OBJ_DIR}/mgba_version.o"
VERSION_SRC="${SRCROOT}/RetroEmu/Core/Bridge/mgba_version.c"
if [ -f "${VERSION_SRC}" ]; then
    clang -std=c11 -O0 ${PLATFORM_FLAGS} -isysroot "${SDKROOT}" \
          -c "${VERSION_SRC}" -o "${VERSION_OBJ}" 2>/dev/null
    [ -f "${VERSION_OBJ}" ] && OBJ_FILES+=("${VERSION_OBJ}")
fi

VALID=()
for obj in "${OBJ_FILES[@]}"; do
    [ -n "$obj" ] && [ -f "$obj" ] && VALID+=("$obj")
done

[ ${#VALID[@]} -eq 0 ] && { echo "Error: no objects compiled"; exit 1; }

echo "Archiving libmgba.a (${#VALID[@]} objects)..."
ar rcs "${LIB_OUT}" "${VALID[@]}"
echo "Built: ${LIB_OUT}"
