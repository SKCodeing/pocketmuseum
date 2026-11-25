#!/bin/bash
# build_nestopia.sh
# 由 Xcode Run Script Phase 调用，将 Nestopia core 编译为静态库
# 在 Xcode Build Phase 中添加：
#   Input Files:  $(SRCROOT)/Nestopia/source/core/NstCore.cpp
#   Output Files: $(BUILT_PRODUCTS_DIR)/libnestopia.a

set -e

SRCROOT="${SRCROOT}"
NESTOPIA_SRC="${SRCROOT}/Nestopia/source/core"
OUTPUT_DIR="${BUILT_PRODUCTS_DIR}"
LIB_OUT="${OUTPUT_DIR}/libnestopia.a"
OBJ_DIR="${DERIVED_FILE_DIR}/nestopia_objs"

# 如果静态库已存在且比源码新，跳过
if [ -f "${LIB_OUT}" ]; then
    NEWEST_SRC=$(find "${NESTOPIA_SRC}" -name "*.cpp" -newer "${LIB_OUT}" | head -1)
    if [ -z "${NEWEST_SRC}" ]; then
        echo "libnestopia.a is up to date, skipping."
        exit 0
    fi
fi

mkdir -p "${OBJ_DIR}"

# 编译标志变更时强制全量重编（删除旧对象文件）
FLAGS_HASH="fexceptions_fno-rtti_c++17"
FLAGS_STAMP="${OBJ_DIR}/.flags_${FLAGS_HASH}"
if [ ! -f "${FLAGS_STAMP}" ]; then
    echo "Compiler flags changed, cleaning old objects..."
    rm -f "${OBJ_DIR}"/*.o
    touch "${FLAGS_STAMP}"
fi

# 编译器标志
CXXFLAGS="-std=c++17 -O2 -fexceptions -fno-rtti \
    -DNDEBUG \
    -Wno-c++11-narrowing \
    -I${NESTOPIA_SRC} \
    -I${NESTOPIA_SRC}/api \
    -arch ${ARCHS} \
    -isysroot ${SDKROOT} \
    -miphoneos-version-min=${IPHONEOS_DEPLOYMENT_TARGET}"

OBJ_FILES=()

# 编译所有 .cpp
while IFS= read -r -d '' CPP_FILE; do
    BASENAME=$(basename "${CPP_FILE}" .cpp)
    OBJ_FILE="${OBJ_DIR}/${BASENAME}.o"
    OBJ_FILES+=("${OBJ_FILE}")
    
    if [ ! -f "${OBJ_FILE}" ] || [ "${CPP_FILE}" -nt "${OBJ_FILE}" ]; then
        echo "Compiling: $(basename ${CPP_FILE})"
        clang++ ${CXXFLAGS} -c "${CPP_FILE}" -o "${OBJ_FILE}" 2>&1 || true
    fi
done < <(find "${NESTOPIA_SRC}" -name "*.cpp" -print0)

# 打包静态库
echo "Archiving libnestopia.a..."
ar rcs "${LIB_OUT}" "${OBJ_FILES[@]}"
echo "Built: ${LIB_OUT}"
