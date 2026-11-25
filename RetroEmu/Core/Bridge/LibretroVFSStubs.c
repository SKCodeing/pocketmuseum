/*
 * LibretroVFSStubs.c
 * 为 libPPSSPPCore-arm64.a 和 libsnes9x-arm64.a 提供 libretro VFS / filestream
 * 以及 path 工具函数的 stub 实现。
 *
 * 这些符号来自 libretro-common，PPSSPP 的 libretro 构建会将它们编译进去，
 * 但 libPPSSPPCore-arm64.a 是以非 libretro 方式构建的，因此需要在宿主端提供。
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>

/* ── libretro VFS 接口类型（最小化定义）─────────────────────────────────── */
typedef struct retro_vfs_file_handle RFILE;

/* ── RFILE 内部结构（与 file_stream.c 保持一致）─────────────────────────── */
struct retro_vfs_file_handle {
    FILE *fp;
    int   err_flag;
};

/* ── filestream_* ─────────────────────────────────────────────────────────── */

RFILE *filestream_open(const char *path, unsigned mode, unsigned hints) {
    (void)hints;
    const char *fmode = "rb";
    /* mode: RETRO_VFS_FILE_ACCESS_READ=1, WRITE=2, READ_WRITE=3 */
    if ((mode & 3) == 3)      fmode = "r+b";
    else if ((mode & 2) == 2) fmode = "wb";
    FILE *fp = fopen(path, fmode);
    if (!fp) return NULL;
    RFILE *f = (RFILE *)calloc(1, sizeof(RFILE));
    if (!f) { fclose(fp); return NULL; }
    f->fp = fp;
    return f;
}

int filestream_close(RFILE *stream) {
    if (!stream) return -1;
    int ret = fclose(stream->fp);
    free(stream);
    return ret;
}

int64_t filestream_read(RFILE *stream, void *s, int64_t len) {
    if (!stream || !s) return -1;
    return (int64_t)fread(s, 1, (size_t)len, stream->fp);
}

int64_t filestream_write(RFILE *stream, const void *s, int64_t len) {
    if (!stream || !s) return -1;
    return (int64_t)fwrite(s, 1, (size_t)len, stream->fp);
}

int64_t filestream_seek(RFILE *stream, int64_t offset, int seek_position) {
    if (!stream) return -1;
    /* seek_position: 0=SET, 1=CUR, 2=END */
    int whence = SEEK_SET;
    if (seek_position == 1) whence = SEEK_CUR;
    else if (seek_position == 2) whence = SEEK_END;
    return fseeko(stream->fp, (off_t)offset, whence);
}

int64_t filestream_tell(RFILE *stream) {
    if (!stream) return -1;
    return (int64_t)ftello(stream->fp);
}

int64_t filestream_get_size(RFILE *stream) {
    if (!stream) return -1;
    off_t cur = ftello(stream->fp);
    fseeko(stream->fp, 0, SEEK_END);
    off_t size = ftello(stream->fp);
    fseeko(stream->fp, cur, SEEK_SET);
    return (int64_t)size;
}

int filestream_flush(RFILE *stream) {
    if (!stream) return -1;
    return fflush(stream->fp);
}

int filestream_eof(RFILE *stream) {
    if (!stream) return 1;
    return feof(stream->fp);
}

int filestream_error(RFILE *stream) {
    if (!stream) return 1;
    return ferror(stream->fp);
}

char *filestream_gets(RFILE *stream, char *s, size_t len) {
    if (!stream || !s) return NULL;
    return fgets(s, (int)len, stream->fp);
}

int filestream_getc(RFILE *stream) {
    if (!stream) return -1;
    return fgetc(stream->fp);
}

int filestream_putc(RFILE *stream, int c) {
    if (!stream) return -1;
    return fputc(c, stream->fp);
}

int filestream_printf(RFILE *stream, const char *fmt, ...) {
    if (!stream) return -1;
    va_list args;
    va_start(args, fmt);
    int ret = vfprintf(stream->fp, fmt, args);
    va_end(args);
    return ret;
}

int filestream_scanf(RFILE *stream, const char *fmt, ...) {
    if (!stream) return -1;
    va_list args;
    va_start(args, fmt);
    int ret = vfscanf(stream->fp, fmt, args);
    va_end(args);
    return ret;
}

int filestream_truncate(RFILE *stream, int64_t len) {
    if (!stream) return -1;
    return ftruncate(fileno(stream->fp), (off_t)len);
}

int filestream_delete(const char *path) {
    if (!path) return -1;
    return remove(path);
}

int filestream_rename(const char *old_path, const char *new_path) {
    if (!old_path || !new_path) return -1;
    return rename(old_path, new_path);
}

/* VFS init stubs */
void filestream_vfs_init(const void *vfs_info) {
    (void)vfs_info;
    /* 使用原生 POSIX 实现，无需初始化 */
}

/* ── rf* 包装（libretro-common file_stream_transforms.c 的简化版）────────── */

RFILE *rfopen(const char *path, const char *mode) {
    FILE *fp = fopen(path, mode);
    if (!fp) return NULL;
    RFILE *f = (RFILE *)calloc(1, sizeof(RFILE));
    if (!f) { fclose(fp); return NULL; }
    f->fp = fp;
    return f;
}

int rfclose(RFILE *stream) {
    return filestream_close(stream);
}

int64_t rfread(void *s, size_t elemSize, size_t count, RFILE *stream) {
    if (!stream || !s) return 0;
    return (int64_t)fread(s, elemSize, count, stream->fp);
}

int64_t rfwrite(const void *s, size_t elemSize, size_t count, RFILE *stream) {
    if (!stream || !s) return 0;
    return (int64_t)fwrite(s, elemSize, count, stream->fp);
}

int rfeof(RFILE *stream) {
    if (!stream) return 1;
    return feof(stream->fp);
}

int rferror(RFILE *stream) {
    if (!stream) return 1;
    return ferror(stream->fp);
}

int rfflush(RFILE *stream) {
    if (!stream) return -1;
    return fflush(stream->fp);
}

char *rfgets(char *s, int size, RFILE *stream) {
    if (!stream || !s) return NULL;
    return fgets(s, size, stream->fp);
}

int rfprintf(RFILE *stream, const char *fmt, ...) {
    if (!stream) return -1;
    va_list args;
    va_start(args, fmt);
    int ret = vfprintf(stream->fp, fmt, args);
    va_end(args);
    return ret;
}

int rfscanf(RFILE *stream, const char *fmt, ...) {
    if (!stream) return -1;
    va_list args;
    va_start(args, fmt);
    int ret = vfscanf(stream->fp, fmt, args);
    va_end(args);
    return ret;
}

int64_t rftell(RFILE *stream) {
    if (!stream) return -1;
    return (int64_t)ftello(stream->fp);
}

int rfseek(RFILE *stream, int64_t offset, int origin) {
    return (int)filestream_seek(stream, offset, origin);
}

/* ── path_* ──────────────────────────────────────────────────────────────── */

int path_is_directory(const char *path) {
    if (!path) return 0;
    struct stat st;
    if (stat(path, &st) != 0) return 0;
    return S_ISDIR(st.st_mode) ? 1 : 0;
}

int path_is_valid(const char *path) {
    if (!path) return 0;
    struct stat st;
    return (stat(path, &st) == 0) ? 1 : 0;
}

int64_t path_get_size(const char *path) {
    if (!path) return -1;
    struct stat st;
    if (stat(path, &st) != 0) return -1;
    return (int64_t)st.st_size;
}

/* ── retro_vfs_mkdir_impl ─────────────────────────────────────────────────── */

int retro_vfs_mkdir_impl(const char *dir) {
    if (!dir) return -1;
    int ret = mkdir(dir, 0755);
    if (ret == 0) return 0;
    if (errno == EEXIST) return -2; /* 已存在 */
    return -1;
}

/* ── path_vfs_init ────────────────────────────────────────────────────────── */

void path_vfs_init(const void *vfs_info) {
    (void)vfs_info;
}
