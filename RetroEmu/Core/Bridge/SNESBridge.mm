// SNESBridge.mm
// Snes9x Super Nintendo 核心桥接实现
// Sprint 2: SNES 平台支持
//
// 依赖：Snes9x 核心库（需在 Xcode 中添加 snes9x 源码或静态库）
// 构建脚本：RetroEmu/Core/build_snes9x.sh
//
// 按键映射（EmulatorButton → Snes9x）：
//   bit0=A, bit1=B, bit2=Select, bit3=Start, bit4=Up, bit5=Down, bit6=Left, bit7=Right
//   SNES 额外按键：X(bit8), Y(bit9), L(bit10), R(bit11)

#import "RetroEmuConfig.h"
#import "SNESBridge.h"
#import <vector>

static const int SNES_WIDTH        = 256;
static const int SNES_HEIGHT       = 224;
static const int SNES_SAMPLE_RATE  = 32000;
// S9xGetSampleCount() 返回的是 int16 总数（L/R 交错），所以每帧容量要 ×2
static const int SNES_SPF          = (SNES_SAMPLE_RATE / 60 + 16) * 2;

// ─────────────────────────────────────────────────────────────────────────────
// Snes9x C API 前向声明（真实集成时由 snes9x.h 提供）
// ─────────────────────────────────────────────────────────────────────────────
#ifdef RETRO_CORE_SNES
// Snes9x 是纯 C++ 库，头文件不能放在 extern "C" 块内
#include "snes9x.h"
#include "memmap.h"
#include "apu/apu.h"
#include "gfx.h"
#include "snapshot.h"
#include "controls.h"
#endif

@implementation SNESBridgeObjC {
    std::vector<uint32_t> _frameBuffer;
    std::vector<int16_t>  _audioBuffer;
    int                   _audioSamples;
    BOOL                  _romLoaded;
    std::vector<uint8_t>  _romData;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _frameBuffer.resize(SNES_WIDTH * SNES_HEIGHT, 0xFF000000);
        _audioBuffer.resize(SNES_SPF, 0);
        _audioSamples = 0;
        _romLoaded    = NO;
    }
    return self;
}

- (BOOL)loadROM:(NSData *)data {
    if (data.length == 0) return NO;
    _romData.assign((const uint8_t*)data.bytes, (const uint8_t*)data.bytes + data.length);

#ifdef RETRO_CORE_SNES
    memset(&Settings, 0, sizeof(Settings));
    Settings.SoundPlaybackRate   = SNES_SAMPLE_RATE;
    Settings.SoundInputRate      = SNES_SAMPLE_RATE;
    Settings.Stereo              = TRUE;
    Settings.SixteenBitSound     = TRUE;
    Settings.Transparency        = TRUE;
    // SupportHiRes was removed in newer Snes9x; hi-res is always supported
    Settings.FrameTimePAL        = 20000;
    Settings.FrameTimeNTSC       = 16667;
    Settings.SkipFrames          = 0;
    Settings.TurboSkipFrames     = 15;
    Settings.CartAName[0]        = 0;
    Settings.CartBName[0]        = 0;

    if (!Memory.Init() || !S9xInitAPU()) {
        NSLog(@"[SNESBridge] Memory/APU init failed");
        return NO;
    }

    // S9xInitDisplay and S9xSetupDefaultKeymap are port-specific;
    // call S9xGraphicsInit instead, and set up a default joypad mapping
    S9xGraphicsInit();
    S9xUnmapAllControls();
    S9xSetController(0, CTL_JOYPAD, 0, 0, 0, 0);
    S9xSetController(1, CTL_JOYPAD, 1, 0, 0, 0);
    S9xVerifyControllers();

    // GFX.Pitch is const in this version; screen buffer is managed internally
    // Set GFX.Screen to point at our buffer (uint16 format)
    GFX.Screen = (uint16_t*)_frameBuffer.data();

    if (!Memory.LoadROMMem(_romData.data(), _romData.size(), nullptr)) {
        NSLog(@"[SNESBridge] LoadROMMem failed");
        return NO;
    }

    S9xReset();
#endif

    _romLoaded = YES;
    NSLog(@"[SNESBridge] ROM loaded (%zu bytes)", data.length);
    return YES;
}

- (void)runFrame {
    if (!_romLoaded) return;

#ifdef RETRO_CORE_SNES
    GFX.Screen = (uint16_t*)_frameBuffer.data();
    S9xMainLoop();
    int samples = S9xGetSampleCount();
    if (samples > 0) {
        int toRead = MIN(samples, SNES_SPF);
        if ((int)_audioBuffer.size() < toRead) _audioBuffer.resize(toRead, 0);
        S9xMixSamples((uint8_t*)_audioBuffer.data(), toRead);
        _audioSamples = toRead;
    } else {
        _audioSamples = 0;
    }
#else
    static uint8_t tick = 0;
    tick++;
    for (int y = 0; y < SNES_HEIGHT; y++) {
        for (int x = 0; x < SNES_WIDTH; x++) {
            uint32_t r = (uint8_t)(x + tick);
            uint32_t g = 0;
            uint32_t b = (uint8_t)(y + tick);
            _frameBuffer[y * SNES_WIDTH + x] = 0xFF000000 | (b << 16) | (g << 8) | r;
        }
    }
    _audioSamples = SNES_SPF;
    memset(_audioBuffer.data(), 0, _audioSamples * sizeof(int16_t));
#endif
}

- (void)reset {
#ifdef RETRO_CORE_SNES
    if (_romLoaded) S9xReset();
#endif
}

- (const uint32_t *)getFrameBuffer { return _frameBuffer.data(); }
- (NSInteger)frameWidth            { return SNES_WIDTH; }
- (NSInteger)frameHeight           { return SNES_HEIGHT; }

- (void)setPlayer1Buttons:(uint16_t)buttons {
#ifdef RETRO_CORE_SNES
    // Map each button using S9xMapButton + S9xReportButton
    // SNES button masks from snes9x.h: B=bit15, Y=bit14, Select=bit13, Start=bit12,
    // Up=bit11, Down=bit10, Left=bit9, Right=bit8, A=bit7, X=bit6, L=bit5, R=bit4
    static bool mapped = false;
    if (!mapped) {
        mapped = true;
        // Map button IDs 0-11 for player 1 (joypad idx 0)
        s9xcommand_t cmd;
        memset(&cmd, 0, sizeof(cmd));
        cmd.type = S9xButtonJoypad;
        cmd.button.joypad.idx = 0;
        uint16_t snes_masks[] = {
            SNES_B_MASK, SNES_A_MASK, SNES_SELECT_MASK, SNES_START_MASK,
            SNES_UP_MASK, SNES_DOWN_MASK, SNES_LEFT_MASK, SNES_RIGHT_MASK,
            SNES_X_MASK, SNES_Y_MASK, SNES_TL_MASK, SNES_TR_MASK
        };
        for (int i = 0; i < 12; i++) {
            cmd.button.joypad.buttons = snes_masks[i];
            S9xMapButton(i, cmd, false);
        }
    }
    for (int i = 0; i < 12; i++) {
        S9xReportButton(i, (buttons >> i) & 1);
    }
#endif
}

- (void)setPlayer2Buttons:(uint16_t)buttons {
#ifdef RETRO_CORE_SNES
    static bool mapped2 = false;
    if (!mapped2) {
        mapped2 = true;
        s9xcommand_t cmd;
        memset(&cmd, 0, sizeof(cmd));
        cmd.type = S9xButtonJoypad;
        cmd.button.joypad.idx = 1;
        uint16_t snes_masks[] = {
            SNES_B_MASK, SNES_A_MASK, SNES_SELECT_MASK, SNES_START_MASK,
            SNES_UP_MASK, SNES_DOWN_MASK, SNES_LEFT_MASK, SNES_RIGHT_MASK,
            SNES_X_MASK, SNES_Y_MASK, SNES_TL_MASK, SNES_TR_MASK
        };
        for (int i = 0; i < 12; i++) {
            cmd.button.joypad.buttons = snes_masks[i];
            S9xMapButton(100 + i, cmd, false); // offset IDs to avoid collision with player 1
        }
    }
    for (int i = 0; i < 12; i++) {
        S9xReportButton(100 + i, (buttons >> i) & 1);
    }
#endif
}

- (const int16_t *)getAudioBuffer { return _audioBuffer.data(); }
- (NSInteger)audioSampleCount    { return _audioSamples; }
- (NSInteger)sampleRate          { return SNES_SAMPLE_RATE; }

- (nullable NSData *)saveState {
    if (!_romLoaded) return nil;
#ifdef RETRO_CORE_SNES
    uint8_t buf[0x20000];
    int sz = S9xFreezeGameMem(buf, sizeof(buf));
    if (sz <= 0) return nil;
    return [NSData dataWithBytes:buf length:sz];
#else
    return nil;
#endif
}

- (BOOL)loadState:(NSData *)data {
    if (!_romLoaded || data.length == 0) return NO;
#ifdef RETRO_CORE_SNES
    return S9xUnfreezeGameMem((const uint8_t*)data.bytes, data.length) == SUCCESS;
#else
    return NO;
#endif
}

- (void)writeByte:(uint8_t)value at:(uint32_t)address {
#ifdef RETRO_CORE_SNES
    S9xSetByte(value, address);
#endif
}

@end
