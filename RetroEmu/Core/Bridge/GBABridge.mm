// GBABridge.mm
// mGBA Game Boy Advance 核心桥接实现

#import "RetroEmuConfig.h"
#import "GBABridge.h"
#import <vector>
#import <string>

// mGBA 需要的宏定义（必须在 include 之前）
#ifndef ENABLE_VFS
#define ENABLE_VFS
#endif
#ifndef COLOR_32_BIT
#define COLOR_32_BIT
#endif
#ifndef MINIMAL_CORE
#define MINIMAL_CORE 2
#endif
#ifndef HAVE_LOCALE
#define HAVE_LOCALE
#endif
#ifndef HAVE_STRLCPY
#define HAVE_STRLCPY
#endif
#ifndef HAVE_STRDUP
#define HAVE_STRDUP
#endif
#ifndef HAVE_STRNDUP
#define HAVE_STRNDUP
#endif

// mGBA C API
extern "C" {
#include <mgba/core/core.h>
#include <mgba/core/serialize.h>
#include <mgba/gba/core.h>
#include <mgba-util/vfs.h>
#include <mgba-util/audio-buffer.h>
}

static const int GBA_WIDTH      = 240;
static const int GBA_HEIGHT     = 160;
static const int GBA_SAMPLE_RATE = 32768;
static const int GBA_SAMPLES_PER_FRAME = GBA_SAMPLE_RATE / 60 + 16;

// GBA 按键位（mGBA 定义）
enum GBAKey {
    GBA_KEY_A      = 0,
    GBA_KEY_B      = 1,
    GBA_KEY_SELECT = 2,
    GBA_KEY_START  = 3,
    GBA_KEY_RIGHT  = 4,
    GBA_KEY_LEFT   = 5,
    GBA_KEY_UP     = 6,
    GBA_KEY_DOWN   = 7,
    GBA_KEY_R      = 8,
    GBA_KEY_L      = 9,
};

@implementation GBABridgeObjC {
    struct mCore*         _core;
    std::vector<uint32_t> _frameBuffer;   // XRGB8 → RGBA
    std::vector<uint32_t> _coreBuffer;    // mGBA 输出缓冲
    std::vector<int16_t>  _audioBuffer;
    std::vector<int16_t>  _monoBuffer;
    std::vector<uint8_t>  _romData;       // 持有 ROM 数据，防止悬空指针
    int                   _audioSamples;
    BOOL                  _romLoaded;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _frameBuffer.resize(GBA_WIDTH * GBA_HEIGHT, 0xFF000000);
        _coreBuffer.resize(GBA_WIDTH * GBA_HEIGHT, 0);
        _audioBuffer.resize(GBA_SAMPLES_PER_FRAME * 2, 0);
        _monoBuffer.resize(GBA_SAMPLES_PER_FRAME, 0);
        _audioSamples = 0;
        _romLoaded    = NO;
        _core         = nullptr;
    }
    return self;
}

- (void)dealloc {
    [self cleanup];
}

- (void)cleanup {
    if (_core) {
        _core->deinit(_core);
        _core = nullptr;
    }
    _romData.clear();
    _romLoaded = NO;
}

- (BOOL)loadROM:(NSData *)data {
    if (data.length == 0) return NO;
    [self cleanup];

    // 直接创建 GBA core（不通过注册表）
    _core = GBACoreCreate();
    if (!_core) {
        NSLog(@"[GBABridge] mCoreCreate failed");
        return NO;
    }

    if (!_core->init(_core)) {
        NSLog(@"[GBABridge] core init failed");
        _core->deinit(_core);
        _core = nullptr;
        return NO;
    }

    // 配置视频缓冲（XRGB8 = uint32）
    _core->setVideoBuffer(_core, (mColor*)_coreBuffer.data(), GBA_WIDTH);

    // 配置音频
    _core->setAudioBufferSize(_core, GBA_SAMPLES_PER_FRAME);

    // 从内存加载 ROM（copy 数据，保证生命周期）
    _romData.assign((const uint8_t*)data.bytes, (const uint8_t*)data.bytes + data.length);
    struct VFile* vf = VFileFromConstMemory(_romData.data(), _romData.size());
    if (!vf) {
        NSLog(@"[GBABridge] VFileFromConstMemory failed");
        [self cleanup];
        return NO;
    }

    if (!_core->loadROM(_core, vf)) {
        NSLog(@"[GBABridge] loadROM failed");
        vf->close(vf);
        [self cleanup];
        return NO;
    }
    // vf 由 core 接管，不需要手动关闭

    // 初始化配置
    mCoreInitConfig(_core, "retroemu");

    // 重置
    _core->reset(_core);

    _romLoaded = YES;
    NSLog(@"[GBABridge] ROM loaded OK (%zu bytes)", data.length);
    return YES;
}

- (void)runFrame {
    if (!_romLoaded || !_core) return;
    _core->runFrame(_core);

    // 转换帧缓冲：XRGB8(0x00RRGGBB) → RGBA(0xFFBBGGRR little-endian)
    const uint32_t *src = _coreBuffer.data();
    uint32_t *dst = _frameBuffer.data();
    for (int i = 0; i < GBA_WIDTH * GBA_HEIGHT; i++) {
        uint32_t px = src[i];
        uint32_t r = (px >> 16) & 0xFF;
        uint32_t g = (px >>  8) & 0xFF;
        uint32_t b =  px        & 0xFF;
        dst[i] = 0xFF000000 | (b << 16) | (g << 8) | r;
    }

    // 读取音频（立体声 → 单声道）
    struct mAudioBuffer* audioBuf = _core->getAudioBuffer(_core);
    if (audioBuf) {
        size_t avail = mAudioBufferAvailable(audioBuf);
        size_t toRead = MIN(avail, (size_t)GBA_SAMPLES_PER_FRAME);
        if (toRead > 0) {
            if (_audioBuffer.size() < toRead * 2) {
                _audioBuffer.resize(toRead * 2, 0);
            }
            mAudioBufferRead(audioBuf, _audioBuffer.data(), toRead);
            // 立体声 → 单声道
            if (_monoBuffer.size() < toRead) _monoBuffer.resize(toRead, 0);
            for (size_t i = 0; i < toRead; i++) {
                int32_t l = _audioBuffer[i * 2];
                int32_t r = _audioBuffer[i * 2 + 1];
                _monoBuffer[i] = (int16_t)((l + r) / 2);
            }
            _audioSamples = (int)toRead;
        } else {
            _audioSamples = 0;
        }
    }
}

- (void)reset {
    if (_core) _core->reset(_core);
}

- (const uint32_t *)getFrameBuffer { return _frameBuffer.data(); }
- (NSInteger)frameWidth            { return GBA_WIDTH; }
- (NSInteger)frameHeight           { return GBA_HEIGHT; }

- (void)setPlayer1Buttons:(uint16_t)buttons {
    if (!_core) return;
    // EmulatorButton: a=0, b=1, select=2, start=3, up=4, down=5, left=6, right=7
    uint32_t keys = 0;
    if (buttons & (1 << 0)) keys |= (1 << GBA_KEY_A);
    if (buttons & (1 << 1)) keys |= (1 << GBA_KEY_B);
    if (buttons & (1 << 2)) keys |= (1 << GBA_KEY_SELECT);
    if (buttons & (1 << 3)) keys |= (1 << GBA_KEY_START);
    if (buttons & (1 << 4)) keys |= (1 << GBA_KEY_UP);
    if (buttons & (1 << 5)) keys |= (1 << GBA_KEY_DOWN);
    if (buttons & (1 << 6)) keys |= (1 << GBA_KEY_LEFT);
    if (buttons & (1 << 7)) keys |= (1 << GBA_KEY_RIGHT);
    _core->setKeys(_core, keys);
}

- (void)setPlayer2Buttons:(uint16_t)buttons { /* GBA 单人 */ }

- (const int16_t *)getAudioBuffer { return _monoBuffer.data(); }
- (NSInteger)audioSampleCount    { return _audioSamples; }
- (NSInteger)sampleRate          { return GBA_SAMPLE_RATE; }

- (nullable NSData *)saveState {
    if (!_romLoaded || !_core) return nil;
    size_t sz = _core->stateSize(_core);
    NSMutableData *data = [NSMutableData dataWithLength:sz];
    if (!_core->saveState(_core, data.mutableBytes)) return nil;
    return data;
}

- (BOOL)loadState:(NSData *)data {
    if (!_romLoaded || !_core || data.length == 0) return NO;
    return _core->loadState(_core, data.bytes);
}

- (void)writeByte:(uint8_t)value at:(uint32_t)address {
    if (!_core) return;
    _core->busWrite8(_core, address, value);
}

@end
