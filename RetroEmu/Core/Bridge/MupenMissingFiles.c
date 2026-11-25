/*
 * MupenMissingFiles.c
 * Mupen64Plus-Core frontend.c 依赖 SDL，无法直接包含。
 * 提供 CoreStartup/CoreShutdown/CoreDoCommand 的最小 stub 实现。
 */
#include <stdint.h>
#include <string.h>
#include <stdio.h>

#include "../../../mupen64plus-core/src/api/m64p_types.h"
#include "../../../mupen64plus-core/src/api/m64p_frontend.h"

EXPORT m64p_error CALL CoreStartup(
    int APIVersion, const char *ConfigPath, const char *DataPath,
    void *Context, void (*DebugCallback)(void *, int, const char *),
    void *Context2, void (*StateCallback)(void *, m64p_core_param, int))
{
    (void)APIVersion; (void)ConfigPath; (void)DataPath;
    (void)Context; (void)DebugCallback; (void)Context2; (void)StateCallback;
    return M64ERR_SUCCESS;
}

EXPORT m64p_error CALL CoreShutdown(void)
{
    return M64ERR_SUCCESS;
}

EXPORT m64p_error CALL CoreDoCommand(m64p_command Command, int ParamInt, void *ParamPtr)
{
    (void)Command; (void)ParamInt; (void)ParamPtr;
    return M64ERR_SUCCESS;
}
