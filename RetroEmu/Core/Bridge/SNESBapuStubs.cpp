// SNESBapuStubs.cpp
// Snes9x BAPU（bsnes APU）子库编译单元
//
// libsnes9x-arm64.a 中的 apu_apu.o 引用了 SNES::DSP、SNES::SMP、
// SNES::SPC_DSP、SNES::dsp、SNES::smp 等符号，这些符号由 bapu 子库提供。
// 由于构建脚本未将 bapu 编译进 libsnes9x-arm64.a，这里通过 include
// bapu 源文件来补充这些符号。
//
// pair 歧义问题已通过将 65c816.h 中的 pair typedef 重命名为 S9xPair
// 并保留 typedef S9xPair pair 别名的方式从源头解决。

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-variable"
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wshadow"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#include "../../../Snes9x/apu/bapu/dsp/sdsp.cpp"
#include "../../../Snes9x/apu/bapu/smp/smp.cpp"
#include "../../../Snes9x/apu/bapu/smp/smp_state.cpp"

#pragma clang diagnostic pop
