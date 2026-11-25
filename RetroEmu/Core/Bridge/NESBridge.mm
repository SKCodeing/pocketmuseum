// NESBridge.mm
// Nestopia NES 核心 ObjC++ 桥接实现

#import "RetroEmuConfig.h"
#import "NESBridge.h"
#import <sstream>
#import <vector>

// Nestopia API（路径由 USER_HEADER_SEARCH_PATHS 解析）
#include "api/NstApiEmulator.hpp"
#include "api/NstApiMachine.hpp"
#include "api/NstApiCartridge.hpp"
#include "api/NstApiInput.hpp"
#include "api/NstApiSound.hpp"
#include "api/NstApiVideo.hpp"
#include "api/NstApiUser.hpp"

// 不使用 using namespace，全部用完整限定名避免歧义

static const int NES_WIDTH         = Nes::Core::Video::Output::WIDTH;   // 256
static const int NES_HEIGHT        = Nes::Core::Video::Output::HEIGHT;  // 240
static const int SAMPLE_RATE       = 44100;
static const int SAMPLES_PER_FRAME = SAMPLE_RATE / 60;

static void NST_CALLBACK userFileCallback(void*, Nes::Api::User::File&) {}

@implementation NESBridgeObjC {
    Nes::Api::Emulator*              _emulator;
    std::vector<uint32_t>            _frameBuffer;
    std::vector<int16_t>             _audioBuffer;
    Nes::Core::Input::Controllers*   _controllers;
    BOOL                             _romLoaded;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _emulator    = new Nes::Api::Emulator();
        _romLoaded   = NO;
        _frameBuffer.resize(NES_WIDTH * NES_HEIGHT, 0xFF000000);
        _audioBuffer.resize(SAMPLES_PER_FRAME, 0);
        _controllers = new Nes::Core::Input::Controllers();
        Nes::Api::User::fileIoCallback.Set(userFileCallback, nullptr);
    }
    return self;
}

- (void)dealloc {
    if (_romLoaded) {
        Nes::Api::Machine(*_emulator).Power(false);
        Nes::Api::Machine(*_emulator).Unload();
    }
    delete _controllers;
    delete _emulator;
}

- (BOOL)loadROM:(NSData *)data {
    if (data.length == 0) return NO;

    if (_romLoaded) {
        Nes::Api::Machine(*_emulator).Power(false);
        Nes::Api::Machine(*_emulator).Unload();
        _romLoaded = NO;
    }

    std::istringstream stream(std::string((const char*)data.bytes, data.length));

    // 加载 ROM
    Nes::Result result = Nes::Api::Machine(*_emulator).Load(
        stream,
        Nes::Api::Machine::FAVORED_NES_NTSC
    );
    if (NES_FAILED(result)) {
        NSLog(@"[NESBridge] Load failed: %d", (int)result);
        return NO;
    }

    // 连接手柄
    Nes::Api::Input(*_emulator).ConnectController(0, Nes::Api::Input::PAD1);
    Nes::Api::Input(*_emulator).ConnectController(1, Nes::Api::Input::PAD2);

    // 配置视频：RGBA8888
    {
        Nes::Api::Video video(*_emulator);
        Nes::Api::Video::RenderState rs;
        rs.filter        = Nes::Api::Video::RenderState::FILTER_NONE;
        rs.width         = NES_WIDTH;
        rs.height        = NES_HEIGHT;
        rs.bits.count    = 32;
        rs.bits.mask.r   = 0x000000FF;
        rs.bits.mask.g   = 0x0000FF00;
        rs.bits.mask.b   = 0x00FF0000;
        if (NES_FAILED(video.SetRenderState(rs))) {
            NSLog(@"[NESBridge] SetRenderState failed");
            return NO;
        }
    }

    // 配置音频
    {
        Nes::Api::Sound sound(*_emulator);
        sound.SetSampleRate(SAMPLE_RATE);
        sound.SetSpeaker(Nes::Api::Sound::SPEAKER_MONO);
        sound.SetVolume(Nes::Api::Sound::ALL_CHANNELS, 85);
    }

    // 开机
    result = Nes::Api::Machine(*_emulator).Power(true);
    if (NES_FAILED(result)) {
        NSLog(@"[NESBridge] Power failed: %d", (int)result);
        return NO;
    }

    _romLoaded = YES;
    NSLog(@"[NESBridge] ROM loaded OK (%zu bytes)", data.length);
    return YES;
}

- (void)runFrame {
    if (!_romLoaded) return;

    Nes::Core::Video::Output videoOut(_frameBuffer.data(),
                                      NES_WIDTH * (int)sizeof(uint32_t));

    Nes::Core::Sound::Output soundOut;
    soundOut.samples[0] = _audioBuffer.data();
    soundOut.length[0]  = (uint)SAMPLES_PER_FRAME;
    soundOut.samples[1] = nullptr;
    soundOut.length[1]  = 0;

    _emulator->Execute(&videoOut, &soundOut, _controllers);
}

- (void)reset {
    if (_romLoaded) {
        Nes::Api::Machine(*_emulator).Reset(false);
    }
    _controllers->pad[0].buttons = 0;
    _controllers->pad[1].buttons = 0;
}

- (const uint32_t *)getFrameBuffer { return _frameBuffer.data(); }
- (NSInteger)frameWidth            { return NES_WIDTH; }
- (NSInteger)frameHeight           { return NES_HEIGHT; }

- (void)setPlayer1Buttons:(uint16_t)buttons {
    _controllers->pad[0].buttons = buttons;
}
- (void)setPlayer2Buttons:(uint16_t)buttons {
    _controllers->pad[1].buttons = buttons;
}

- (const int16_t *)getAudioBuffer { return _audioBuffer.data(); }
- (NSInteger)audioSampleCount     { return SAMPLES_PER_FRAME; }
- (NSInteger)sampleRate           { return SAMPLE_RATE; }

- (nullable NSData *)saveState {
    if (!_romLoaded) return nil;
    std::stringstream ss;
    Nes::Api::Machine machine(*_emulator);
    if (NES_FAILED(machine.SaveState(ss, Nes::Api::Machine::NO_COMPRESSION))) return nil;
    const std::string& str = ss.str();
    return [NSData dataWithBytes:str.data() length:str.size()];
}

- (BOOL)loadState:(NSData *)data {
    if (!_romLoaded || data.length == 0) return NO;
    std::istringstream ss(std::string((const char*)data.bytes, data.length));
    Nes::Api::Machine machine(*_emulator);
    return !NES_FAILED(machine.LoadState(ss));
}

- (void)writeByte:(uint8_t)value at:(uint32_t)address {
    // Nestopia 未暴露直接内存写入 API，作弊码暂不支持 NES
    (void)value; (void)address;
}

@end
