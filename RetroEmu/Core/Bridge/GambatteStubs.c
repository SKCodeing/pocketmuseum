// GambatteStubs.c
// 提供 Gambatte 依赖的 libretro 符号 stub，避免引入整个 libretro 层

#include <stdarg.h>
#include <stdio.h>

// gambatte_log 的 stub 实现，直接输出到 stderr
void gambatte_log(int level, const char *format, ...) {
    va_list args;
    va_start(args, format);
    vfprintf(stderr, format, args);
    va_end(args);
}

void gambatte_log_set_cb(void *log_cb) {
    // 不需要实现
    (void)log_cb;
}
