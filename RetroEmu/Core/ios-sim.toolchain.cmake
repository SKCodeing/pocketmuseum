# ios-sim.toolchain.cmake
# iOS Simulator (Apple Silicon, arm64-sim) 交叉编译工具链
# 与 ios.toolchain.cmake 一一对应，只替换 SDK / 目标平台 / 版本宏

set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR arm64)

execute_process(
    COMMAND xcrun --sdk iphonesimulator --show-sdk-path
    OUTPUT_VARIABLE SIM_SDK
    OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT SIM_SDK)
    message(FATAL_ERROR "找不到 iPhoneSimulator SDK，请确认 Xcode 命令行工具已选中")
endif()

execute_process(
    COMMAND xcrun --sdk iphonesimulator --find clang
    OUTPUT_VARIABLE SIM_CLANG
    OUTPUT_STRIP_TRAILING_WHITESPACE)

set(CMAKE_C_COMPILER   ${SIM_CLANG})
set(CMAKE_CXX_COMPILER ${SIM_CLANG}++)

set(CMAKE_OSX_SYSROOT        ${SIM_SDK})
set(CMAKE_OSX_ARCHITECTURES  arm64)
set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0")

# 模拟器 SDK 把 system() 标记为 unavailable，PPSSPP 靠 MOBILE_DEVICE 宏关掉
# Common/File/FileUtil.cpp 里的 open-in-editor 分支（Android 构建的同款开关）。
# 这里走编译宏而不是 CMake 变量，避免 MOBILE_DEVICE=ON 触发 SDL2 查找。
set(COMMON_FLAGS "-arch arm64 -isysroot ${SIM_SDK} -mios-simulator-version-min=14.0 -DMOBILE_DEVICE")
set(CMAKE_C_FLAGS   "${COMMON_FLAGS}" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS "${COMMON_FLAGS}" CACHE STRING "" FORCE)

set(CMAKE_FIND_ROOT_PATH ${SIM_SDK})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
