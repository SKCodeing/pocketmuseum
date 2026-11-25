/*
 * PCXSMissingFiles.c
 * 为 PCSX-ReARMed 提供链接时缺失的全局变量和函数 stub。
 *
 * libpcsx-arm64.a 编译时未定义 DRC_DISABLE，导致 psxRegs 和 rcnts
 * 这两个全局变量被条件编译排除在外。这里直接定义它们。
 */
#include <sys/param.h>
#include <stdint.h>
#include <string.h>

/* ── psxRegs：CPU 寄存器组（r3000a.c 里被 #ifdef DRC_DISABLE 保护）── */
#include "../../../pcsx_rearmed/libpcsxcore/r3000a.h"
psxRegisters psxRegs;

/* ── rcnts：计数器数组（psxcounters.c 里被 #ifdef DRC_DISABLE 保护）── */
#include "../../../pcsx_rearmed/libpcsxcore/psxcounters.h"
#define CounterQuantity 4
Rcnt rcnts[CounterQuantity];

/* ── misc.c: BiosBootBypass, CheckCdrom, LoadCdrom, LoadCdromFile, calcCrc ── */
#include "../../../pcsx_rearmed/libpcsxcore/misc.c"

/* ── plugin_lib.c 依赖 libpicofe（子模块未初始化），改用 stub ── */
unsigned short in_keystate[8] = {0};
void pl_frame_limit(void) {}

/* ── psxRec stub（dynarec 在 iOS 上不可用）── */
R3000Acpu psxRec = {0};

/* ── ndrc stubs（new_dynarec 在 iOS 上不可用）── */
/* ndrc_g: new_dynarec 全局状态，database.c 引用 */
#include "../../../pcsx_rearmed/libpcsxcore/new_dynarec/new_dynarec.h"
struct ndrc_globals ndrc_g = {0};

/* ndrc_freeze: SaveState/LoadState 时序列化 dynarec 状态 */
void ndrc_freeze(void *f, int mode) {
    (void)f; (void)mode;
    /* dynarec 未启用，无需序列化 */
}

/* ── OpenPlugins / ClosePlugins stubs ─────────────────────────────────────
 * 这两个函数属于 pcsx_rearmed/frontend 层（frontend/main.c），
 * 不在 libpcsxcore 中。PS1Bridge.mm 调用了 OpenPlugins(0)，
 * 这里提供最小化 stub：直接调用 libpcsxcore 的 LoadPlugins()。
 * ─────────────────────────────────────────────────────────────────────── */
#include "../../../pcsx_rearmed/libpcsxcore/plugins.h"

int OpenPlugins(int load_memcards) {
    (void)load_memcards;
    /* 在 iOS 上使用内置插件，无需动态加载 */
    return 0;
}

void ClosePlugins(void) {
    /* stub */
}
