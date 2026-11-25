// NDSBridge.mm
// melonDS Nintendo DS 核心桥接实现

#import "RetroEmuConfig.h"
#import "NDSBridge.h"
#import <vector>

static const int NDS_WIDTH         = 256;
static const int NDS_SCREEN_HEIGHT = 192;
static const int NDS_HEIGHT        = NDS_SCREEN_HEIGHT * 2;
static const int NDS_SAMPLE_RATE   = 48000;   // melonDS 默认输出 48kHz，必须与桥接声明一致，否则变调
static const int NDS_SPF           = NDS_SAMPLE_RATE / 60 + 16;

// ─────────────────────────────────────────────────────────────────────────────
// melonDS 需要 Platform 回调实现（最小化 stub）
// ─────────────────────────────────────────────────────────────────────────────
#ifdef RETRO_CORE_NDS
#include "NDS.h"
#include "GPU.h"
#include "SPU.h"
#include "NDSCart.h"
#include "Platform.h"
#include "Savestate.h"

using namespace melonDS;

namespace melonDS::Platform {

void SignalStop(StopReason reason, void* userdata) {}

FileHandle* OpenFile(const std::string& path, FileMode mode) { return nullptr; }
FileHandle* OpenLocalFile(const std::string& path, FileMode mode) { return nullptr; }
std::string GetLocalFilePath(const std::string& filename) { return ""; }
bool FileExists(const std::string& name) { return false; }
bool LocalFileExists(const std::string& name) { return false; }
bool CheckFileWritable(const std::string& filepath) { return false; }
bool CheckLocalFileWritable(const std::string& filepath) { return false; }
bool CloseFile(FileHandle* file) { return false; }
bool IsEndOfFile(FileHandle* file) { return true; }
bool FileReadLine(char* str, int count, FileHandle* file) { return false; }
u64  FilePosition(FileHandle* file) { return 0; }
bool FileSeek(FileHandle* file, s64 offset, FileSeekOrigin origin) { return false; }
void FileRewind(FileHandle* file) {}
u64  FileRead(void* data, u64 size, u64 count, FileHandle* file) { return 0; }
bool FileFlush(FileHandle* file) { return false; }
u64  FileWrite(const void* data, u64 size, u64 count, FileHandle* file) { return 0; }
u64  FileWriteFormatted(FileHandle* file, const char* fmt, ...) { return 0; }
u64  FileLength(FileHandle* file) { return 0; }

void Log(LogLevel level, const char* fmt, ...) {}

Thread* Thread_Create(std::function<void()> func) { return nullptr; }
void Thread_Free(Thread* thread) {}
void Thread_Wait(Thread* thread) {}

Semaphore* Semaphore_Create() { return nullptr; }
void Semaphore_Free(Semaphore* sema) {}
void Semaphore_Reset(Semaphore* sema) {}
void Semaphore_Wait(Semaphore* sema) {}
bool Semaphore_TryWait(Semaphore* sema, int timeout_ms) { return false; }
void Semaphore_Post(Semaphore* sema, int count) {}

Mutex* Mutex_Create() { return nullptr; }
void Mutex_Free(Mutex* mutex) {}
void Mutex_Lock(Mutex* mutex) {}
void Mutex_Unlock(Mutex* mutex) {}
bool Mutex_TryLock(Mutex* mutex) { return false; }

void Sleep(u64 usecs) {}
u64 GetMSCount() { return 0; }
u64 GetUSCount() { return 0; }

void WriteNDSSave(const u8* savedata, u32 savelen, u32 writeoffset, u32 writelen, void* userdata) {}
void WriteGBASave(const u8* savedata, u32 savelen, u32 writeoffset, u32 writelen, void* userdata) {}
void WriteFirmware(const Firmware& firmware, u32 writeoffset, u32 writelen, void* userdata) {}
void WriteDateTime(int year, int month, int day, int hour, int minute, int second, void* userdata) {}

void MP_Begin(void* userdata) {}
void MP_End(void* userdata) {}
int  MP_SendPacket(u8* data, int len, u64 timestamp, void* userdata) { return 0; }
int  MP_RecvPacket(u8* data, u64* timestamp, void* userdata) { return 0; }
int  MP_SendCmd(u8* data, int len, u64 timestamp, void* userdata) { return 0; }
int  MP_SendReply(u8* data, int len, u64 timestamp, u16 aid, void* userdata) { return 0; }
int  MP_SendAck(u8* data, int len, u64 timestamp, void* userdata) { return 0; }
int  MP_RecvHostPacket(u8* data, u64* timestamp, void* userdata) { return 0; }
u16  MP_RecvReplies(u8* data, u64 timestamp, u16 aidmask, void* userdata) { return 0; }

int  Net_SendPacket(u8* data, int len, void* userdata) { return 0; }
int  Net_RecvPacket(u8* data, void* userdata) { return 0; }

void Camera_Start(int num, void* userdata) {}
void Camera_Stop(int num, void* userdata) {}
void Camera_CaptureFrame(int num, u32* frame, int width, int height, bool yuv, void* userdata) {}

void Mic_Start(void* userdata) {}
void Mic_Stop(void* userdata) {}
int  Mic_ReadInput(s16* data, int maxlength, void* userdata) { return 0; }

AACDecoder* AAC_Init() { return nullptr; }
void AAC_DeInit(AACDecoder* dec) {}
bool AAC_Configure(AACDecoder* dec, int frequency, int channels) { return false; }
bool AAC_DecodeFrame(AACDecoder* dec, const void* input, int inputlen, void* output, int outputlen) { return false; }

bool Addon_KeyDown(KeyType type, void* userdata) { return false; }
void Addon_RumbleStart(u32 len, void* userdata) {}
void Addon_RumbleStop(void* userdata) {}
float Addon_MotionQuery(MotionQueryType type, void* userdata) { return 0.0f; }

DynamicLibrary* DynamicLibrary_Load(const char* lib) { return nullptr; }
void DynamicLibrary_Unload(DynamicLibrary* lib) {}
void* DynamicLibrary_LoadFunction(DynamicLibrary* lib, const char* name) { return nullptr; }

} // namespace melonDS::Platform
#endif

@implementation NDSBridgeObjC {
    std::vector<uint32_t> _frameBuffer;
    std::vector<int16_t>  _audioBuffer;
    int                   _audioSamples;
    BOOL                  _romLoaded;
    std::vector<uint8_t>  _romData;
#ifdef RETRO_CORE_NDS
    melonDS::NDS*         _nds;
#endif
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _frameBuffer.resize(NDS_WIDTH * NDS_HEIGHT, 0xFF000000);
        _audioBuffer.resize(NDS_SPF * 2, 0);
        _audioSamples = 0;
        _romLoaded    = NO;
#ifdef RETRO_CORE_NDS
        _nds = nullptr;
#endif
    }
    return self;
}

- (void)dealloc {
#ifdef RETRO_CORE_NDS
    if (_nds) {
        delete _nds;
        _nds = nullptr;
    }
#endif
}

- (BOOL)loadROM:(NSData *)data {
    if (data.length == 0) return NO;
    _romData.assign((const uint8_t*)data.bytes, (const uint8_t*)data.bytes + data.length);

#ifdef RETRO_CORE_NDS
    // 清理旧实例
    if (_nds) { delete _nds; _nds = nullptr; }

    // 创建 NDS 实例（使用默认构造，内置 FreeBIOS）
    _nds = new melonDS::NDS();

    // 解析并插入 ROM
    auto cart = melonDS::NDSCart::ParseROM(_romData.data(), (uint32_t)_romData.size());
    if (!cart) {
        NSLog(@"[NDSBridge] ParseROM failed");
        delete _nds; _nds = nullptr;
        return NO;
    }
    _nds->SetNDSCart(std::move(cart));
    _nds->Reset();
    // 显式锁死输出采样率，避免依赖 melonDS 默认值导致变调
    _nds->SPU.SetOutputSampleRate(NDS_SAMPLE_RATE);
#endif

    _romLoaded = YES;
    NSLog(@"[NDSBridge] ROM loaded (%zu bytes)", data.length);
    return YES;
}

- (void)runFrame {
    if (!_romLoaded) return;

#ifdef RETRO_CORE_NDS
    _nds->RunFrame();

    // 获取帧缓冲（软件渲染器返回 32-bit BGRA，256x192 每屏）
    void* topScreen   = nullptr;
    void* botScreen   = nullptr;
    if (_nds->GPU.GetFramebuffers(&topScreen, &botScreen)) {
        uint32_t* dst = _frameBuffer.data();
        if (topScreen)
            memcpy(dst, topScreen, NDS_WIDTH * NDS_SCREEN_HEIGHT * sizeof(uint32_t));
        if (botScreen)
            memcpy(dst + NDS_WIDTH * NDS_SCREEN_HEIGHT, botScreen, NDS_WIDTH * NDS_SCREEN_HEIGHT * sizeof(uint32_t));
    }

    // 读取音频
    int samples = _nds->SPU.GetOutputSize();
    if (samples > 0) {
        int toRead = MIN(samples, NDS_SPF);
        if ((int)_audioBuffer.size() < toRead * 2) _audioBuffer.resize(toRead * 2, 0);
        // GetOutputSize() 返回的是立体声帧数，ReadOutput 每帧写 L/R 两个 int16
        _nds->SPU.ReadOutput(_audioBuffer.data(), toRead);
        _audioSamples = toRead * 2;
    } else {
        _audioSamples = 0;
    }
#else
    static uint8_t tick = 0; tick++;
    for (int y = 0; y < NDS_HEIGHT; y++) {
        for (int x = 0; x < NDS_WIDTH; x++) {
            uint32_t g = (uint8_t)(x + tick), b = (uint8_t)(y + tick);
            if (y == NDS_SCREEN_HEIGHT - 1 || y == NDS_SCREEN_HEIGHT) { g = b = 0x80; }
            _frameBuffer[y * NDS_WIDTH + x] = 0xFF000000 | (b << 16) | (g << 8);
        }
    }
    _audioSamples = NDS_SPF * 2;
    memset(_audioBuffer.data(), 0, _audioSamples * sizeof(int16_t));
#endif
}

- (void)reset {
#ifdef RETRO_CORE_NDS
    if (_nds && _romLoaded) _nds->Reset();
#endif
}

- (const uint32_t *)getFrameBuffer { return _frameBuffer.data(); }
- (NSInteger)frameWidth            { return NDS_WIDTH; }
- (NSInteger)frameHeight           { return NDS_HEIGHT; }

- (void)setPlayer1Buttons:(uint16_t)buttons {
#ifdef RETRO_CORE_NDS
    if (!_nds) return;
    // NDS KeyInput: bit0=A, bit1=B, bit2=Select, bit3=Start,
    //               bit4=Right, bit5=Left, bit6=Up, bit7=Down, bit8=R, bit9=L
    // 0 = pressed, 1 = released (active low)
    uint32_t keys = 0x3FF; // all released
    if (buttons & (1 << 0)) keys &= ~(1 << 0); // A
    if (buttons & (1 << 1)) keys &= ~(1 << 1); // B
    if (buttons & (1 << 2)) keys &= ~(1 << 2); // Select
    if (buttons & (1 << 3)) keys &= ~(1 << 3); // Start
    if (buttons & (1 << 7)) keys &= ~(1 << 4); // Right
    if (buttons & (1 << 6)) keys &= ~(1 << 5); // Left
    if (buttons & (1 << 4)) keys &= ~(1 << 6); // Up
    if (buttons & (1 << 5)) keys &= ~(1 << 7); // Down
    if (buttons & (1 << 11)) keys &= ~(1 << 8); // R
    if (buttons & (1 << 10)) keys &= ~(1 << 9); // L
    _nds->SetKeyMask(keys);
#endif
}

- (void)setPlayer2Buttons:(uint16_t)buttons {}

- (void)touchScreenAt:(float)x y:(float)y {
#ifdef RETRO_CORE_NDS
    if (!_nds) return;
    int tx = MAX(0, MIN(255, (int)(x * 255.0f)));
    int ty = MAX(0, MIN(191, (int)(y * 191.0f)));
    _nds->TouchScreen((uint16_t)tx, (uint16_t)ty);
#endif
}

- (void)touchScreenRelease {
#ifdef RETRO_CORE_NDS
    if (_nds) _nds->ReleaseScreen();
#endif
}

- (const int16_t *)getAudioBuffer { return _audioBuffer.data(); }
- (NSInteger)audioSampleCount    { return _audioSamples; }
- (NSInteger)sampleRate          { return NDS_SAMPLE_RATE; }

- (nullable NSData *)saveState {
    if (!_romLoaded) return nil;
#ifdef RETRO_CORE_NDS
    if (!_nds) return nil;
    melonDS::Savestate* state = new melonDS::Savestate(melonDS::Savestate::DEFAULT_SIZE);
    _nds->DoSavestate(state);
    state->Finish();
    NSData* data = [NSData dataWithBytes:state->Buffer() length:state->Length()];
    delete state;
    return data;
#else
    return nil;
#endif
}

- (BOOL)loadState:(NSData *)data {
    if (!_romLoaded || data.length == 0) return NO;
#ifdef RETRO_CORE_NDS
    if (!_nds) return NO;
    melonDS::Savestate* state = new melonDS::Savestate((void*)data.bytes, (uint32_t)data.length, false);
    _nds->DoSavestate(state);
    delete state;
    return YES;
#else
    return NO;
#endif
}

- (void)writeByte:(uint8_t)value at:(uint32_t)address {
#ifdef RETRO_CORE_NDS
    if (_nds) _nds->ARM9Write8((uint32_t)address, (uint8_t)value);
#endif
}

@end
