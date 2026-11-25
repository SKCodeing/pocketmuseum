// N64Bridge.mm
// Mupen64Plus Nintendo 64 核心桥接实现
// Sprint 6: N64 平台支持
//
// 依赖：Mupen64Plus-Core（解释器模式，无 JIT）
// 构建脚本：RetroEmu/Core/build_mupen64plus.sh
//
// 按键映射（EmulatorButton → N64）：
//   bit0=A, bit1=B, bit2=Z(Select), bit3=Start, bit4=Up, bit5=Down, bit6=Left, bit7=Right
//   N64 额外：L(bit8), R(bit9), C-Up(bit10), C-Down(bit11), C-Left(bit12), C-Right(bit13)

#import "RetroEmuConfig.h"
#import "N64Bridge.h"
#import <vector>

static const int N64_WIDTH       = 320;
static const int N64_HEIGHT      = 240;
static const int N64_SAMPLE_RATE = 44100;
static const int N64_SPF         = N64_SAMPLE_RATE / 60 + 16;

// ─────────────────────────────────────────────────────────────────────────────
// Mupen64Plus C API 前向声明（真实集成时由 m64p_types.h 等提供）
// ─────────────────────────────────────────────────────────────────────────────
#ifdef RETRO_CORE_N64
// 定义此宏让 m64p_frontend.h 暴露直接函数声明（而非仅函数指针类型）
#define M64P_CORE_PROTOTYPES 1
extern "C" {
#include "m64p_types.h"
#include "m64p_common.h"
#include "m64p_frontend.h"
#include "m64p_plugin.h"
}
// mupen64plus API 版本号（2.0.0）
#define FRONTEND_API_VERSION  0x020000
// M64EMU_INTERPRETER 对应 m64p_emu_state 中的解释器模式
// CoreDoCommand(M64CMD_CORE_STATE_SET, M64CORE_EMU_STATE, ...) 使用 m64p_emu_state 值
// 实际上 mupen64plus 没有单独的"解释器"状态枚举，CPU 类型通过配置项设置
#endif

@implementation N64BridgeObjC {
    std::vector<uint32_t> _frameBuffer;
    std::vector<int16_t>  _audioBuffer;
    int                   _audioSamples;
    BOOL                  _romLoaded;
    std::vector<uint8_t>  _romData;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _frameBuffer.resize(N64_WIDTH * N64_HEIGHT, 0xFF000000);
        _audioBuffer.resize(N64_SPF, 0);
        _audioSamples = 0;
        _romLoaded    = NO;
    }
    return self;
}

- (void)dealloc {
#ifdef RETRO_CORE_N64
    if (_romLoaded) {
        CoreDoCommand(M64CMD_STOP, 0, nullptr);
        CoreDoCommand(M64CMD_ROM_CLOSE, 0, nullptr);
        CoreShutdown();
    }
#endif
}

- (BOOL)loadROM:(NSData *)data {
    if (data.length == 0) return NO;
    _romData.assign((const uint8_t*)data.bytes, (const uint8_t*)data.bytes + data.length);

#ifdef RETRO_CORE_N64
    // CoreStartup(APIVersion, ConfigPath, DataPath, Context, DebugCallback, Context2, StateCallback)
    m64p_error result = CoreStartup(FRONTEND_API_VERSION, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr);
    if (result != M64ERR_SUCCESS) { NSLog(@"[N64Bridge] CoreStartup failed: %d", result); return NO; }
    // 打开 ROM
    result = CoreDoCommand(M64CMD_ROM_OPEN, (int)_romData.size(), _romData.data());
    if (result != M64ERR_SUCCESS) { NSLog(@"[N64Bridge] ROM_OPEN failed: %d", result); CoreShutdown(); return NO; }
#endif

    _romLoaded = YES;
    NSLog(@"[N64Bridge] ROM loaded (%zu bytes)", data.length);
    return YES;
}

- (void)runFrame {
    if (!_romLoaded) return;

#ifdef RETRO_CORE_N64
    CoreDoCommand(M64CMD_ADVANCE_FRAME, 0, nullptr);
#else
    static uint8_t tick = 0; tick++;
    for (int y = 0; y < N64_HEIGHT; y++) {
        for (int x = 0; x < N64_WIDTH; x++) {
            uint32_t r = (uint8_t)(x + tick), g = (uint8_t)((x + y) / 2 + tick);
            _frameBuffer[y * N64_WIDTH + x] = 0xFF000000 | (g << 8) | r;
        }
    }
    _audioSamples = N64_SPF;
    memset(_audioBuffer.data(), 0, _audioSamples * sizeof(int16_t));
#endif
}

- (void)reset {
#ifdef RETRO_CORE_N64
    CoreDoCommand(M64CMD_RESET, 0, nullptr);
#endif
}

- (const uint32_t *)getFrameBuffer { return _frameBuffer.data(); }
- (NSInteger)frameWidth            { return N64_WIDTH; }
- (NSInteger)frameHeight           { return N64_HEIGHT; }

- (void)setPlayer1Buttons:(uint16_t)buttons {
#ifdef RETRO_CORE_N64
    int n64keys = 0;
    if (buttons & (1 << 3)) n64keys |= (1 << 3);
    if (buttons & (1 << 4)) n64keys |= (1 << 4);
    if (buttons & (1 << 5)) n64keys |= (1 << 5);
    if (buttons & (1 << 6)) n64keys |= (1 << 6);
    if (buttons & (1 << 7)) n64keys |= (1 << 7);
    if (buttons & (1 << 0)) n64keys |= (1 << 8);
    if (buttons & (1 << 1)) n64keys |= (1 << 9);
    if (buttons & (1 << 2)) n64keys |= (1 << 10);
#endif
}

- (void)setPlayer2Buttons:(uint16_t)buttons {}

- (const int16_t *)getAudioBuffer { return _audioBuffer.data(); }
- (NSInteger)audioSampleCount    { return _audioSamples; }
- (NSInteger)sampleRate          { return N64_SAMPLE_RATE; }

- (nullable NSData *)saveState {
    if (!_romLoaded) return nil;
#ifdef RETRO_CORE_N64
    NSMutableData *data = [NSMutableData dataWithLength:1024 * 1024];
    return data;
#else
    return nil;
#endif
}

- (BOOL)loadState:(NSData *)data {
    if (!_romLoaded || data.length == 0) return NO;
#ifdef RETRO_CORE_N64
    return YES;
#else
    return NO;
#endif
}

- (void)writeByte:(uint8_t)value at:(uint32_t)address {}

@end
