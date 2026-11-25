// GBCBridge.mm
// Gambatte GBC 核心 ObjC++ 桥接实现

#import "RetroEmuConfig.h"
#import "GBCBridge.h"
#import <vector>
#import <sstream>

#include "gambatte.h"

// GBC 屏幕尺寸
static const int GBC_WIDTH  = 160;
static const int GBC_HEIGHT = 144;

static const int SAMPLES_PER_FRAME = 35112;
static const int AUDIO_BUF_SIZE    = SAMPLES_PER_FRAME + 2064;
static const int SAMPLE_RATE_OUT   = 44100;
// Gambatte 原生输出约 2.1MHz（35112 样本/帧），需要重采样到 44100
static const double GBC_NATIVE_RATE = 2097152.0;
static const double GBC_RESAMPLE_STEP = GBC_NATIVE_RATE / (double)SAMPLE_RATE_OUT;

static unsigned mapButtons(uint16_t b) {
    unsigned g = 0;
    if (b & 0x01) g |= gambatte::InputGetter::A;
    if (b & 0x02) g |= gambatte::InputGetter::B;
    if (b & 0x04) g |= gambatte::InputGetter::SELECT;
    if (b & 0x08) g |= gambatte::InputGetter::START;
    if (b & 0x10) g |= gambatte::InputGetter::UP;
    if (b & 0x20) g |= gambatte::InputGetter::DOWN;
    if (b & 0x40) g |= gambatte::InputGetter::LEFT;
    if (b & 0x80) g |= gambatte::InputGetter::RIGHT;
    return g;
}

class GBCInputGetter : public gambatte::InputGetter {
public:
    unsigned buttons = 0;
    unsigned operator()() override { return buttons; }
};

@implementation GBCBridgeObjC {
    gambatte::GB*                          _gb;
    GBCInputGetter*                        _inputGetter;
    std::vector<gambatte::video_pixel_t>   _frameBuffer;  // 与 Gambatte 类型一致
    std::vector<uint32_t>                  _rgbaBuffer;   // 转换后供 Metal 使用（RGBA32）
    std::vector<gambatte::uint_least32_t>  _soundBuf;
    std::vector<int16_t>                   _monoNative;
    std::vector<int16_t>                   _audioBuf;
    int                                    _audioSamples;
    double                                 _resamplePos;
    BOOL                                   _romLoaded;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _gb          = new gambatte::GB();
        _inputGetter = new GBCInputGetter();
        _romLoaded   = NO;
        _audioSamples = 0;
        _frameBuffer.resize(GBC_WIDTH * GBC_HEIGHT, 0xFF000000);
        _rgbaBuffer.resize(GBC_WIDTH * GBC_HEIGHT, 0xFF000000);
        _soundBuf.resize(AUDIO_BUF_SIZE, 0);
        _monoNative.resize(AUDIO_BUF_SIZE, 0);
        _audioBuf.resize(SAMPLES_PER_FRAME, 0);
        _resamplePos  = 0.0;
        _gb->setInputGetter(_inputGetter);
    }
    return self;
}

- (void)dealloc {
    delete _gb;
    delete _inputGetter;
}

- (BOOL)loadROM:(NSData *)data {
    if (data.length == 0) return NO;
    int result = _gb->load(data.bytes, (unsigned)data.length, 0);
    if (result != 0) {
        NSLog(@"[GBCBridge] load failed: %d", result);
        return NO;
    }
    _romLoaded = YES;
    NSLog(@"[GBCBridge] ROM loaded OK (%zu bytes)", data.length);
    return YES;
}

- (void)runFrame {
    if (!_romLoaded) return;

    unsigned totalSamples = 0;
    long ret = -1;

    while (ret < 0) {
        unsigned req = SAMPLES_PER_FRAME;
        ret = _gb->runFor(
            _frameBuffer.data(), GBC_WIDTH,
            _soundBuf.data() + totalSamples,
            AUDIO_BUF_SIZE - totalSamples,
            req
        );
        totalSamples += req;
        if (totalSamples >= (unsigned)AUDIO_BUF_SIZE) break;
    }

    // video_pixel_t → uint32_t（RGBA），Gambatte 输出 XRGB，转成 RGBA
    for (int i = 0; i < GBC_WIDTH * GBC_HEIGHT; i++) {
        uint32_t px = (uint32_t)_frameBuffer[i];
        // Gambatte: 0x00RRGGBB → Metal 需要 0xFFRRGGBB（RGBA little-endian = ABGR）
        _rgbaBuffer[i] = 0xFF000000 | (px & 0x00FFFFFF);
    }

    // 立体声 → 单声道
    int nativeCount = (int)totalSamples;
    if (nativeCount > AUDIO_BUF_SIZE) nativeCount = AUDIO_BUF_SIZE;
    for (int i = 0; i < nativeCount; i++) {
        int16_t left  = (int16_t)(_soundBuf[i] & 0xFFFF);
        int16_t right = (int16_t)((_soundBuf[i] >> 16) & 0xFFFF);
        _monoNative[i] = (int16_t)(((int)left + (int)right) / 2);
    }

    // 盒式滤波重采样：Gambatte 原生 ~2.1MHz → 44100Hz
    // （不重采样直接把 35112 个样本当 44100Hz 播会严重变慢/变调；
    //   简单地隔点取值又会把高频全折成噪声，所以对每个输出点覆盖的区间取平均）
    int outCount = 0;
    double pos = _resamplePos;
    while (outCount < SAMPLES_PER_FRAME) {
        double next = pos + GBC_RESAMPLE_STEP;
        if (next >= (double)nativeCount) break;
        int start = (int)pos;
        int end   = (int)next;              // 不含
        if (end <= start) end = start + 1;
        int sum = 0;
        for (int i = start; i < end; i++) sum += _monoNative[i];
        _audioBuf[outCount++] = (int16_t)(sum / (end - start));
        pos = next;
    }
    _resamplePos = pos - (double)nativeCount;   // 相位跨帧保持，避免每帧边界爆音
    if (_resamplePos < 0.0) _resamplePos = 0.0;
    _audioSamples = outCount;
}

- (void)reset {
    if (_romLoaded) _gb->reset();
    _inputGetter->buttons = 0;
    _resamplePos = 0.0;
}

- (const uint32_t *)getFrameBuffer { return _rgbaBuffer.data(); }
- (NSInteger)frameWidth            { return GBC_WIDTH; }
- (NSInteger)frameHeight           { return GBC_HEIGHT; }

- (void)setPlayer1Buttons:(uint16_t)buttons {
    _inputGetter->buttons = mapButtons(buttons);
}
- (void)setPlayer2Buttons:(uint16_t)buttons { /* GBC 单人 */ }

- (const int16_t *)getAudioBuffer { return _audioBuf.data(); }
- (NSInteger)audioSampleCount    { return _audioSamples; }
- (NSInteger)sampleRate          { return SAMPLE_RATE_OUT; }

- (nullable NSData *)saveState {
    if (!_romLoaded) return nil;
    size_t sz = _gb->stateSize();
    NSMutableData *data = [NSMutableData dataWithLength:sz];
    _gb->saveState(data.mutableBytes);
    return data;
}

- (BOOL)loadState:(NSData *)data {
    if (!_romLoaded || data.length == 0) return NO;
    _gb->loadState(data.bytes);
    return YES;
}

- (void)writeByte:(uint8_t)value at:(uint32_t)address {
    // Gambatte 暂不暴露直接内存写入接口，留空
    (void)value; (void)address;
}

@end
