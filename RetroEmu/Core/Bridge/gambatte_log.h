// gambatte_log.h - stub，替换 libretro 版本，去掉对 libretro.h 的依赖
#ifndef _GAMBATTE_LOG_H
#define _GAMBATTE_LOG_H

#ifdef __cplusplus
extern "C" {
#endif

typedef enum { RETRO_LOG_DEBUG = 0, RETRO_LOG_INFO, RETRO_LOG_WARN, RETRO_LOG_ERROR } retro_log_level;
static inline void gambatte_log_set_cb(void *cb) { (void)cb; }
static inline void gambatte_log(retro_log_level level, const char *format, ...) { (void)level; (void)format; }

#ifdef __cplusplus
}
#endif

#endif
