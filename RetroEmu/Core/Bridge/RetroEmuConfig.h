// RetroEmuConfig.h
// 各模拟器核心集成状态配置
//
// 说明：
//   - 已集成真实 C++ 库的核心：取消注释对应的 #define
//   - 未集成的核心保持注释状态，Bridge 会使用内置 Stub（彩色测试画面）
//
// ⚠️ 如果在 Xcode Build Settings → Preprocessor Macros 里已经设置了对应宏，
//    则删除这里的 #define，避免重复定义。

// ── 已集成核心 ──────────────────────────────────────────────────────────────

// NES: Nestopia（RetroEmu/Core/core/ 目录下有完整源码）
#ifndef RETRO_CORE_NES
#define RETRO_CORE_NES 1
#endif

// GBC: Gambatte（RetroEmu/Core/src/ 目录下有完整源码）
#ifndef RETRO_CORE_GBC
#define RETRO_CORE_GBC 1
#endif

// GG / SMS / MD / 32X / SegaCD: Genesis-Plus-GX（GenesisPlus/ 目录下有完整源码）
#ifndef RETRO_CORE_GENESIS
#define RETRO_CORE_GENESIS 1
#endif

// GBA: mGBA（已集成静态库）
#ifndef RETRO_CORE_GBA
#define RETRO_CORE_GBA 1
#endif

// PSP: PPSSPP（libs/ppsspp/libPPSSPPCore-arm64.a ✅ 已编译）
#ifndef RETRO_CORE_PSP
#define RETRO_CORE_PSP 1
#endif

// SNES: Snes9x（libs/snes9x/libsnes9x-arm64.a ✅ 已编译）
#ifndef RETRO_CORE_SNES
#define RETRO_CORE_SNES 1
#endif

// NDS: melonDS（libs/melonds/libmelonDS-arm64.a ✅ 已编译）
#ifndef RETRO_CORE_NDS
#define RETRO_CORE_NDS 1
#endif

// N64: Mupen64Plus（libs/mupen64plus/libmupen64plus-arm64.a ✅ 已编译）
#ifndef RETRO_CORE_N64
#define RETRO_CORE_N64 1
#endif

// PS1: PCSX-ReARMed（libs/pcsx/libpcsx-arm64.a ✅ 已编译）
#ifndef RETRO_CORE_PS1
#define RETRO_CORE_PS1 1
#endif

// ── 全局宏（当任意核心启用时自动定义，供 Swift 层判断）────────────────────────
#if defined(RETRO_CORE_NES) || defined(RETRO_CORE_GBC) || defined(RETRO_CORE_GENESIS) || \
    defined(RETRO_CORE_GBA) || defined(RETRO_CORE_PSP) || defined(RETRO_CORE_SNES)    || \
    defined(RETRO_CORE_NDS) || defined(RETRO_CORE_N64) || defined(RETRO_CORE_PS1)
#ifndef RETRO_NATIVE_CORE
#define RETRO_NATIVE_CORE 1
#endif
#endif
