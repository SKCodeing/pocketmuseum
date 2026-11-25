// SMSMDBridge.mm
// Genesis-Plus-GX SMS / Mega Drive 桥接实现
// SMS: 256x192, MD: 320x224（viewport 动态）

#import "RetroEmuConfig.h"
#import "SMSMDBridge.h"
#import <vector>

#include "gg_osd.h"

extern "C" {
#include "genesis_core.h"
#include "cart_hw/md_cart.h"   // HW_ADDON_* 常量
}

// ---- 全局变量（与 GGBridge.mm 共享同一套 Genesis-Plus-GX 全局状态）----
// 注意：同一时刻只能运行一个 Genesis-Plus-GX 实例
// config / cart_size / yx5200_* 已在 GGBridge.mm 定义，这里不重复定义

static const int GX_SAMPLE_RATE = 44100;
static const int GX_BMP_WIDTH   = 720;
static const int GX_BMP_HEIGHT  = 576;

// SMS 默认分辨率
static const int SMS_WIDTH  = 256;
static const int SMS_HEIGHT = 192;
// MD 默认分辨率（viewport 可变）
static const int MD_WIDTH   = 320;
static const int MD_HEIGHT  = 224;

static void gx_config_init_sms(void) {
    memset(&config, 0, sizeof(config));
    config.hq_fm        = 1;
    config.ym2413       = 1;  // 必须为1，否则 YM_Update=NULL 导致崩溃
    config.psg_preamp   = 150;
    config.fm_preamp    = 100;
    config.cdda_volume  = 100;
    config.pcm_volume   = 100;
    config.system       = 0;
    config.region_detect = 0;
    config.bios         = 0;
    config.no_sprite_limit = 1;
    config.overclock    = 0;
    config.input[0].device  = 0;
    config.input[0].port    = 0;
    config.input[0].padtype = 0;
}

static void gx_config_init_md(void) {
    gx_config_init_sms();
    config.hq_fm   = 1;
    config.ym2612  = 0;
    config.fm_preamp = 100;
}

// PE-1: Sega 32X 配置
// 注意：GenesisPlus GX 通过 ROM 文件头自动检测 32X，无需额外 add_on 标志
static void gx_config_init_32x(void) {
    gx_config_init_md();
    // 32X 由 load_rom() 根据文件头自动识别，config 无需特殊设置
}

// PE-1: Sega CD 配置
static void gx_config_init_cd(void) {
    gx_config_init_md();
    config.add_on    = HW_ADDON_MEGACD;  // 启用 Mega CD 扩展
    config.cdda_volume = 100;
    config.pcm_volume  = 100;
}

@implementation SMSMDBridgeObjC {
    SMSMDSystemType       _systemType;
    std::vector<uint32_t> _frameBuffer;
    std::vector<uint8_t>  _bmpData;
    std::vector<int16_t>  _audioBuffer;
    std::vector<int16_t>  _monoBuffer;
    int                   _audioSamples;
    int                   _frameW;
    int                   _frameH;
    BOOL                  _romLoaded;
}

- (instancetype)initWithSystem:(SMSMDSystemType)system {
    self = [super init];
    if (self) {
        _systemType   = system;
        _frameW       = (system == SMSMDSystemTypeMD) ? MD_WIDTH  : SMS_WIDTH;
        _frameH       = (system == SMSMDSystemTypeMD) ? MD_HEIGHT : SMS_HEIGHT;
        _frameBuffer.resize(_frameW * _frameH, 0xFF000000);
        _bmpData.resize(GX_BMP_WIDTH * GX_BMP_HEIGHT * 4, 0);
        // blip_new(samplerate/10) 最多输出 4410 个立体声对 = 8820 个 int16，留余量
        _audioBuffer.resize((GX_SAMPLE_RATE / 10 + 64) * 2, 0);
        _audioSamples = 0;
        _romLoaded    = NO;
    }
    return self;
}

- (BOOL)loadROM:(NSData *)data {
    if (data.length == 0) return NO;

    // 写临时文件，扩展名决定 Genesis-Plus-GX 的系统检测
    NSString *ext;
    switch (_systemType) {
        case SMSMDSystemTypeMD:      ext = @"md";  break;
        case SMSMDSystemTypeSega32X: ext = @"32x"; break;
        case SMSMDSystemTypeSegaCD:  ext = @"cue"; break;  // Sega CD 用 .cue
        default:                     ext = @"sms"; break;
    }
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"game.%@", ext]];
    if (![data writeToFile:tmpPath atomically:YES]) return NO;

    // 初始化配置
    switch (_systemType) {
        case SMSMDSystemTypeMD:      gx_config_init_md();  break;
        case SMSMDSystemTypeSega32X: gx_config_init_32x(); break;
        case SMSMDSystemTypeSegaCD:  gx_config_init_cd();  break;
        default:                     gx_config_init_sms(); break;
    }

    // 初始化 bitmap（32bpp）
    memset(&bitmap, 0, sizeof(bitmap));
    bitmap.data   = _bmpData.data();
    bitmap.width  = GX_BMP_WIDTH;
    bitmap.height = GX_BMP_HEIGHT;
    bitmap.pitch  = GX_BMP_WIDTH * 4;

    // 初始化音频
    if (audio_init(GX_SAMPLE_RATE, 0) < 0) return NO;

    // 加载 ROM
    char path[1024];
    strncpy(path, tmpPath.UTF8String, 1023);
    if (!load_rom(path)) {
        audio_shutdown();
        return NO;
    }

    // 配置输入
    if (_systemType == SMSMDSystemTypeMD ||
        _systemType == SMSMDSystemTypeSega32X ||
        _systemType == SMSMDSystemTypeSegaCD) {
        input.system[0] = SYSTEM_GAMEPAD;
        input.system[1] = SYSTEM_GAMEPAD;
        input.dev[0]    = DEVICE_PAD3B;
        input.dev[1]    = DEVICE_PAD3B;
    } else {
        input.system[0] = SYSTEM_GAMEPAD;
        input.system[1] = NO_SYSTEM;
        input.dev[0]    = DEVICE_PAD2B;
    }
    input.pad[0] = 0;
    input.pad[1] = 0;

    system_init();
    audio_reset();
    system_reset();

    _romLoaded = YES;
    NSLog(@"[SMSMDBridge] ROM loaded, system=%d system_hw=0x%02x", (int)_systemType, system_hw);
    return YES;
}

- (void)runFrame {
    if (!_romLoaded) return;

    if (!snd.blips[0]) {
        audio_init(GX_SAMPLE_RATE, 0);
        audio_reset();
    }

    if (_systemType == SMSMDSystemTypeMD ||
        _systemType == SMSMDSystemTypeSega32X ||
        _systemType == SMSMDSystemTypeSegaCD) {
        system_frame_gen(0);
    } else {
        system_frame_sms(0);
    }

    // 从 viewport 提取画面
    int vx = bitmap.viewport.x;
    int vy = bitmap.viewport.y;
    int vw = bitmap.viewport.w;
    int vh = bitmap.viewport.h;

    if (vw > 0 && vh > 0) {
        _frameW = vw;
        _frameH = vh;
        if ((int)_frameBuffer.size() < vw * vh) {
            _frameBuffer.resize(vw * vh, 0xFF000000);
        }
    }

    for (int y = 0; y < _frameH; y++) {
        const uint32_t *src = (const uint32_t *)(bitmap.data +
            ((vy + y) * bitmap.pitch)) + vx;
        uint32_t *dst = _frameBuffer.data() + y * _frameW;
        for (int x = 0; x < _frameW; x++) {
            uint32_t px = src[x];
            uint32_t r = (px >> 16) & 0xFF;
            uint32_t g = (px >>  8) & 0xFF;
            uint32_t b =  px        & 0xFF;
            dst[x] = 0xFF000000 | (b << 16) | (g << 8) | r;
        }
    }

    if (snd.blips[0] && snd.enabled) {
        int sz = sound_update(mcycles_vdp);
        if (sz > 0) {
            if (sz * 2 > (int)_audioBuffer.size()) {
                _audioBuffer.resize(sz * 2 + 64, 0);
            }
            blip_read_samples(snd.blips[0], _audioBuffer.data(), sz);
        }
        _audioSamples = sz;
    } else {
        _audioSamples = 0;
    }
}
- (void)reset {
    if (_romLoaded) {
        audio_reset();
        system_reset();
    }
    input.pad[0] = 0;
    input.pad[1] = 0;
}

- (const uint32_t *)getFrameBuffer { return _frameBuffer.data(); }
- (NSInteger)frameWidth            { return _frameW; }
- (NSInteger)frameHeight           { return _frameH; }

- (void)setPlayer1Buttons:(uint16_t)buttons {
    // EmulatorButton → Genesis INPUT_*
    // a=bit0, b=bit1, select=bit2, start=bit3, up=bit4, down=bit5, left=bit6, right=bit7
    uint16_t pad = 0;
    if (buttons & (1 << 4)) pad |= INPUT_UP;
    if (buttons & (1 << 5)) pad |= INPUT_DOWN;
    if (buttons & (1 << 6)) pad |= INPUT_LEFT;
    if (buttons & (1 << 7)) pad |= INPUT_RIGHT;
    if (_systemType == SMSMDSystemTypeMD) {
        if (buttons & (1 << 0)) pad |= INPUT_A;   // A → A
        if (buttons & (1 << 1)) pad |= INPUT_B;   // B → B
        if (buttons & (1 << 2)) pad |= INPUT_C;   // Select → C
        if (buttons & (1 << 3)) pad |= INPUT_START;
    } else {
        if (buttons & (1 << 0)) pad |= INPUT_BUTTON1;
        if (buttons & (1 << 1)) pad |= INPUT_BUTTON2;
        if (buttons & (1 << 3)) pad |= INPUT_START;
    }
    input.pad[0] = pad;
}

- (void)setPlayer2Buttons:(uint16_t)buttons {
    if (_systemType != SMSMDSystemTypeMD) return;
    uint16_t pad = 0;
    if (buttons & (1 << 4)) pad |= INPUT_UP;
    if (buttons & (1 << 5)) pad |= INPUT_DOWN;
    if (buttons & (1 << 6)) pad |= INPUT_LEFT;
    if (buttons & (1 << 7)) pad |= INPUT_RIGHT;
    if (buttons & (1 << 0)) pad |= INPUT_A;
    if (buttons & (1 << 1)) pad |= INPUT_B;
    if (buttons & (1 << 2)) pad |= INPUT_C;
    if (buttons & (1 << 3)) pad |= INPUT_START;
    input.pad[1] = pad;
}

- (const int16_t *)getAudioBuffer {
    // 立体声交错 → 单声道（L+R 平均）
    int count = _audioSamples;
    if ((int)_monoBuffer.size() < count) _monoBuffer.resize(count, 0);
    const int16_t *src = _audioBuffer.data();
    for (int i = 0; i < count; i++) {
        int32_t l = src[i * 2];
        int32_t r = src[i * 2 + 1];
        _monoBuffer[i] = (int16_t)((l + r) / 2);
    }
    return _monoBuffer.data();
}
- (NSInteger)audioSampleCount    { return _audioSamples; }
- (NSInteger)sampleRate          { return GX_SAMPLE_RATE; }

- (nullable NSData *)saveState {
    if (!_romLoaded) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:STATE_SIZE];
    int saved = state_save((unsigned char *)data.mutableBytes);
    if (saved <= 0) return nil;
    return [data subdataWithRange:NSMakeRange(0, saved)];
}

- (BOOL)loadState:(NSData *)data {
    if (!_romLoaded || data.length == 0) return NO;
    NSMutableData *buf = [NSMutableData dataWithLength:STATE_SIZE];
    memcpy(buf.mutableBytes, data.bytes, MIN(data.length, STATE_SIZE));
    return state_load((unsigned char *)buf.mutableBytes) > 0;
}

- (void)writeByte:(uint8_t)value at:(uint32_t)address {
    if (!_romLoaded) return;
    // SMS/GG Z80 RAM: 0xC000-0xDFFF
    if (_systemType == SMSMDSystemTypeSMS && address >= 0xC000 && address <= 0xDFFF) {
        zram[address & 0x1FFF] = value;
    }
    // MD 68K RAM: 0xFF0000-0xFFFFFF
    if (_systemType == SMSMDSystemTypeMD && address >= 0xFF0000) {
        work_ram[address & 0xFFFF] = value;
    }
}

- (BOOL)loadBIOS:(NSData *)biosData {
    // PE-1: Sega CD BIOS 加载
    // GenesisPlus GX 通过 load_bios() 从文件系统读取 BIOS
    // 将 BIOS 写入临时目录，设置 config.bios 标志后由 system_init() 自动加载
    if (biosData.length == 0) return NO;
    NSString *biosPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"bios_CD_U.bin"];
    if (![biosData writeToFile:biosPath atomically:YES]) return NO;
    // config.bios = 1 告知核心使用 BIOS；实际路径由 load_bios() 从 config 的 bios_path 读取
    // GenesisPlus GX 的 bios 路径通过 osd.h 中的 get_config_path() 获取
    // 此处将 BIOS 写入临时目录，核心会在 system_init() 时自动查找
    config.bios = 1;
    NSLog(@"[SMSMDBridge] Sega CD BIOS written to: %@ (%zu bytes)", biosPath, biosData.length);
    return YES;
}

@end
