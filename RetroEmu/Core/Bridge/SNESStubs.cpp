// SNESStubs.cpp
// Snes9x 宿主端回调 stub 实现
// Snes9x 核心库要求宿主端提供这些函数，否则链接失败。
// 这里提供最小化实现，满足链接需求，实际功能由 SNESBridge.mm 驱动。

#include "snes9x.h"
#include "display.h"
#include "gfx.h"
#include "apu/apu.h"
#include "controls.h"
#include "snapshot.h"
#include "fscompat.h"
#include "messages.h"
#include "memmap.h"
#include <cstdio>
#include <cstring>
#include <string>

// ── 消息 ────────────────────────────────────────────────────────────────────
void S9xMessage(int type, int number, const char *message) {
    (void)type; (void)number;
    if (message) fprintf(stderr, "[Snes9x] %s\n", message);
}

// ── 显示 / 帧更新 ────────────────────────────────────────────────────────────
bool8 S9xInitUpdate(void)     { return TRUE; }
bool8 S9xDeinitUpdate(int w, int h) { (void)w; (void)h; return TRUE; }
bool8 S9xContinueUpdate(int w, int h) { (void)w; (void)h; return TRUE; }
void  S9xSyncSpeed(void)      {}

// ── 声音设备 ─────────────────────────────────────────────────────────────────
bool8 S9xOpenSoundDevice(void) { return TRUE; }

// ── 输入轮询 ─────────────────────────────────────────────────────────────────
bool S9xPollButton(uint32 id, bool *pressed) {
    (void)id;
    if (pressed) *pressed = false;
    return true;
}
bool S9xPollPointer(uint32 id, int16 *x, int16 *y) {
    (void)id;
    if (x) *x = 0;
    if (y) *y = 0;
    return true;
}
bool S9xPollAxis(uint32 id, int16 *value) {
    (void)id;
    if (value) *value = 0;
    return true;
}
void S9xHandlePortCommand(s9xcommand_t cmd, int16 data1, int16 data2) {
    (void)cmd; (void)data1; (void)data2;
}

// ── 文件系统 ─────────────────────────────────────────────────────────────────
std::string S9xGetDirectory(enum s9x_getdirtype type) {
    (void)type;
    const char *tmpdir = getenv("TMPDIR");
    if (!tmpdir) tmpdir = "/tmp";
    return std::string(tmpdir);
}
std::string S9xGetFilenameInc(std::string ext, enum s9x_getdirtype type) {
    (void)type;
    const char *tmpdir = getenv("TMPDIR");
    if (!tmpdir) tmpdir = "/tmp";
    return std::string(tmpdir) + "/save" + ext;
}

// ── 快照文件 ─────────────────────────────────────────────────────────────────
#include "stream.h"

bool8 S9xOpenSnapshotFile(const char *fname, bool8 read_only, STREAM *file) {
    if (!fname || !file) return FALSE;
    const char *mode = read_only ? "rb" : "wb";
    FILE *fp = fopen(fname, mode);
    if (!fp) return FALSE;
    *file = new fStream(fp);
    return TRUE;
}
void S9xCloseSnapshotFile(STREAM file) {
    if (file) {
        file->closeStream();
        delete file;
    }
}

// ── 字符串输入 ───────────────────────────────────────────────────────────────
const char *S9xStringInput(const char *msg) {
    (void)msg;
    return nullptr;
}

// ── SRAM 自动保存 ────────────────────────────────────────────────────────────
void S9xAutoSaveSRAM(void) {}

// ── 声道切换 ─────────────────────────────────────────────────────────────────
void S9xToggleSoundChannel(int c) { (void)c; }

// ── 退出 ─────────────────────────────────────────────────────────────────────
void S9xExit(void) {}

// ── display.h 其余接口（链接需要）────────────────────────────────────────────
void S9xUsage(void) {}
char *S9xParseArgs(char **, int) { return nullptr; }
void S9xParseArgsForCheats(char **, int) {}
void S9xLoadConfigFiles(char **, int) {}
// S9xSetInfoString 已由 libsnes9x-arm64.a(gfx.o) 提供，不在此重复定义
void S9xPutImage(int, int) {}
void S9xInitDisplay(int, char **) {}
void S9xDeinitDisplay(void) {}
void S9xTextMode(void) {}
void S9xGraphicsMode(void) {}
void S9xExtraUsage(void) {}
void S9xParseArg(char **, int &, int) {}
void S9xExtraDisplayUsage(void) {}
void S9xParseDisplayArg(char **, int &, int) {}
void S9xSetTitle(const char *) {}
void S9xInitInputDevices(void) {}
void S9xProcessEvents(bool8) {}
const char *S9xSelectFilename(const char *, const char *, const char *, const char *) { return nullptr; }

// ── SNES::SPC_State_Copier 已由 SNESBapuStubs.cpp 通过 include SPC_DSP.cpp 提供 ──
// 不再需要在此处重复定义。
