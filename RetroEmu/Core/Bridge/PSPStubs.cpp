// PSPStubs.cpp
// PPSSPP 宿主端回调 stub 实现
// libPPSSPPCore-arm64.a 及其依赖库要求宿主端提供这些符号。
// 这里提供最小化实现，满足链接需求。

#include <string>
#include <string_view>
#include <vector>
#include <functional>
#include <cstdio>
#include <cstring>

#include "Common/System/System.h"
#include "Common/System/NativeApp.h"

// ── System_* 属性查询 ────────────────────────────────────────────────────────
std::string System_GetProperty(SystemProperty prop) {
    switch (prop) {
        case SYSPROP_NAME:          return "iOS";
        case SYSPROP_LANGREGION:    return "zh_CN";
        case SYSPROP_CPUINFO:       return "ARM64";
        case SYSPROP_BUILD_VERSION: return "1.0";
        default:                    return "";
    }
}

std::vector<std::string> System_GetPropertyStringVec(SystemProperty prop) {
    (void)prop;
    return {};
}

int64_t System_GetPropertyInt(SystemProperty prop) {
    switch (prop) {
        case SYSPROP_AUDIO_SAMPLE_RATE:              return 44100;
        case SYSPROP_AUDIO_FRAMES_PER_BUFFER:        return 1024;
        case SYSPROP_AUDIO_OPTIMAL_SAMPLE_RATE:      return 44100;
        case SYSPROP_AUDIO_OPTIMAL_FRAMES_PER_BUFFER:return 1024;
        case SYSPROP_DISPLAY_XRES:                   return 1920;
        case SYSPROP_DISPLAY_YRES:                   return 1080;
        case SYSPROP_DISPLAY_REFRESH_RATE:           return 60;
        case SYSPROP_DEVICE_TYPE:                    return DEVICE_TYPE_MOBILE;
        case SYSPROP_SYSTEMVERSION:                  return 15;
        default:                                     return 0;
    }
}

float System_GetPropertyFloat(SystemProperty prop) {
    switch (prop) {
        case SYSPROP_DISPLAY_SAFE_INSET_LEFT:
        case SYSPROP_DISPLAY_SAFE_INSET_RIGHT:
        case SYSPROP_DISPLAY_SAFE_INSET_TOP:
        case SYSPROP_DISPLAY_SAFE_INSET_BOTTOM: return 0.0f;
        default:                                return 0.0f;
    }
}

bool System_GetPropertyBool(SystemProperty prop) {
    switch (prop) {
        case SYSPROP_CAN_JIT:              return false; // App Store 合规
        case SYSPROP_SUPPORTS_HTTPS:       return true;
        case SYSPROP_HAS_BACK_BUTTON:      return false;
        case SYSPROP_HAS_KEYBOARD:         return true;
        case SYSPROP_KEYBOARD_IS_SOFT:     return true;
        case SYSPROP_LIMITED_FILE_BROWSING:return true;
        case SYSPROP_USE_APP_STORE:        return true;
        default:                           return false;
    }
}

// ── System_* 通知 / 消息 ─────────────────────────────────────────────────────
void System_Notify(SystemNotification notification) {
    (void)notification;
}

void System_PostUIMessage(UIMessage message, std::string_view param) {
    (void)message; (void)param;
}

// ── System_* 请求 ────────────────────────────────────────────────────────────
bool System_MakeRequest(SystemRequestType type, int requestId,
                        const std::string &param1, const std::string &param2,
                        int64_t param3, int64_t param4) {
    (void)type; (void)requestId; (void)param1; (void)param2;
    (void)param3; (void)param4;
    return false;
}

// ── System_* 主线程调度 ──────────────────────────────────────────────────────
void System_RunOnMainThread(std::function<void()> func) {
    // 在当前线程直接执行（stub 实现）
    if (func) func();
}

// ── System_* 音频 ────────────────────────────────────────────────────────────
// 前向声明：PSPBridge.mm 里定义的音频队列入口
extern "C" void PSPBridge_PushAudio(const int32_t *samples, int numSamples, float volume);
extern "C" void PSPBridge_ClearAudio(void);

void System_AudioPushSamples(const int32_t *audio, int numSamples, float volume) {
    if (!audio || numSamples <= 0) return;
    PSPBridge_PushAudio(audio, numSamples, volume);
}

void System_AudioClear() {
    PSPBridge_ClearAudio();
}

void System_AudioGetDebugStats(char *buf, size_t bufSize) {
    if (buf && bufSize > 0) buf[0] = '\0';
}

// ── System_* 相机 ────────────────────────────────────────────────────────────
std::vector<std::string> System_GetCameraDeviceList() {
    return {};
}

// ── System_* 其他 ────────────────────────────────────────────────────────────
void System_Toast(std::string_view text) { (void)text; }
void System_ShowKeyboard() {}
void System_Vibrate(int length_ms) { (void)length_ms; }
void System_LaunchUrl(LaunchUrlType urlType, std::string_view url) {
    (void)urlType; (void)url;
}

PermissionStatus System_GetPermissionStatus(SystemPermission permission) {
    (void)permission;
    return PERMISSION_STATUS_GRANTED;
}
void System_AskForPermission(SystemPermission permission) { (void)permission; }

bool System_AudioRecordingIsAvailable() { return false; }
bool System_AudioRecordingState()       { return false; }

// ── NativeApp.h 要求的回调 ───────────────────────────────────────────────────
bool NativeSaveSecret(std::string_view nameOfSecret, std::string_view data) {
    (void)nameOfSecret; (void)data;
    return false;
}

std::string NativeLoadSecret(std::string_view nameOfSecret) {
    (void)nameOfSecret;
    return "";
}

// ── Identifier（Common/File/Path.h 等需要）──────────────────────────────────
// Identifier 类在 PPSSPP 的 Common 库中定义，但构造函数可能未被导出。
// 如果链接时仍报 Identifier::Identifier 缺失，在此提供 stub。
// （通常 libCommon.a 已包含，此处作为保险）
