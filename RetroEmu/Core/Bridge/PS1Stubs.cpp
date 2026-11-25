// PS1Stubs.cpp
// PCSX-ReARMed 宿主端回调 stub 实现
//
// 规则：
//   - 库里标记为 U（undefined）的符号 → 我们必须提供定义
//   - 库里标记为 C（common）的符号   → 库自己已有弱定义，我们不能重复定义
//
// 需要我们提供的（U）：
//   SysPrintf, SysMessage, SysLoadLibrary, SysLoadSym, SysLibError,
//   SysCloseLibrary, SaveFuncs, CdromId,
//   ISOinit/shutdown/open/close/getTN/getTD/readTrack/readCDDA/readSub/getStatus,
//   ISOgetBuffer, PAD1_readPort/startPoll/poll, PAD2_readPort/startPoll/poll,
//   BiosBootBypass, CheckCdrom, LoadCdrom, LoadCdromFile
//
// 已在库里定义（C，不能重复）：
//   Mcd1Data, Mcd2Data, McdDisable, McdFlag,
//   GPU_*, SPU_*（函数指针，库里是 common symbol，链接时会合并）

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdarg>

extern "C" {
// 用完整相对路径包含 PCSX 头文件，避免与 GenesisPlus/core/system.h 同名冲突
// 先包含 <sys/param.h> 提供 MAXPATHLEN，psxcommon.h 需要它
#include <sys/param.h>
#include "psemu_plugin_defs.h"
#include "psxcommon.h"
#include "../../pcsx_rearmed/libpcsxcore/system.h"
#include "plugins.h"
#include "cdriso.h"
#include "misc.h"
#include "sio.h"
}

// ── 系统回调 ─────────────────────────────────────────────────────────────────
void SysPrintf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
}

void SysMessage(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
}

void *SysLoadLibrary(const char *lib) { (void)lib; return nullptr; }
void *SysLoadSym(void *lib, const char *sym) { (void)lib; (void)sym; return nullptr; }
const char *SysLibError(void) { return "not supported"; }
void SysCloseLibrary(void *lib) { (void)lib; }
void SysRunGui(void) {}
void SysClose(void) {}

// ── ISO CDRom 函数（U 符号，必须提供）────────────────────────────────────────
static void *_isoGetBuffer(void) { return nullptr; }
void *(*ISOgetBuffer)(void) = _isoGetBuffer;

int ISOinit(void)    { return 0; }
int ISOshutdown(void){ return 0; }
int ISOopen(const char *fname) { (void)fname; return 0; }
int ISOclose(void)   { return 0; }
int ISOgetTN(unsigned char *buf) {
    if (buf) { buf[0] = 1; buf[1] = 1; }
    return 0;
}
int ISOgetTD(int track, unsigned char *buf) {
    (void)track;
    if (buf) memset(buf, 0, 4);
    return 0;
}
int ISOreadTrack(const unsigned char *time, void *buf) {
    (void)time;
    if (buf) memset(buf, 0, 2352);
    return 0;
}
int ISOreadCDDA(const unsigned char *time, void *buf) {
    (void)time;
    if (buf) memset(buf, 0, 2352);
    return 0;
}
int ISOreadSub(const unsigned char *time, void *buf) {
    (void)time;
    if (buf) memset(buf, 0, 96);
    return 0;
}
int ISOgetStatus(struct CdrStat *stat) {
    if (stat) memset(stat, 0, sizeof(*stat));
    return 0;
}

// ── PAD 手柄（libpcsx-arm64.a 的 pad.o 已提供，这里只提供 readPort）────────
void PAD1_readPort(struct PadDataS *pad, int *is_multitap) {
    if (pad)         memset(pad, 0, sizeof(*pad));
    if (is_multitap) *is_multitap = 0;
}

void PAD2_readPort(struct PadDataS *pad, int *is_multitap) {
    if (pad)         memset(pad, 0, sizeof(*pad));
    if (is_multitap) *is_multitap = 0;
}

// ── SaveFuncs 和 CdromId 由 PCXSMissingFiles.c 通过 include misc.c 提供 ──────

// ── 平台回调 ─────────────────────────────────────────────────────────────────
void pl_gun_byte2(int port, unsigned char byte) { (void)port; (void)byte; }
void plat_trigger_vibrate(int pad, int low, int high) { (void)pad;(void)low;(void)high; }
