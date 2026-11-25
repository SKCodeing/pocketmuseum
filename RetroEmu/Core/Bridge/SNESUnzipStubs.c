/*
 * SNESUnzipStubs.c
 * 为 libsnes9x-arm64.a 提供 unzip 压缩格式支持。
 *
 * libsnes9x-arm64.a 中的 loadzip.o、memmap.o、msu1.o、stream.o 引用了
 * unzOpen/unzClose 等 minizip 符号。
 * 这里通过 include snes9x 自带的 unzip 源文件来提供这些符号。
 */

/* ── minizip / unzip ─────────────────────────────────────────────────────── */
#include "../../../Snes9x/unzip/ioapi.c"
#include "../../../Snes9x/unzip/unzip.c"
