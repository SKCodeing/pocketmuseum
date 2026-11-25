// GGBridge.mm
// Genesis-Plus-GX Game Gear 核心 ObjC++ 桥接实现

#import "RetroEmuConfig.h"
#import "GGBridge.h"
#import <vector>

// ---- Genesis-Plus-GX 平台适配 ----
// 必须在 shared.h 之前包含，提供 osd.h 所需的所有定义
#include "gg_osd.h"

// GenesisPlus 核心头文件，用相对路径 wrapper 避免与 Gambatte 同名头文件冲突
extern "C" {
#include "genesis_core.h"
}

// ---- 全局配置变量定义（osd.h 声明，这里定义）----
t_config config;
char GG_ROM[256]     = "";
char AR_ROM[256]     = "";
char SK_ROM[256]     = "";
char SK_UPMEM[256]   = "";
char GG_BIOS[256]    = "";
char MD_BIOS[256]    = "";
char CD_BIOS_EU[256] = "";
char CD_BIOS_US[256] = "";
char CD_BIOS_JP[256] = "";
char MS_BIOS_US[256] = "";
char MS_BIOS_EU[256] = "";
char MS_BIOS_JP[256] = "";

// ---- 平台回调实现 ----
// ---- YX5200 stub 和 cart_size 必须在 extern "C" 块里，保持 C linkage ----
extern "C" {
    void osd_input_update(void) {}
    void ROMCheatUpdate(void) {}

    // YX5200 stub（GG 游戏不使用此芯片，yx5200.c 因缺少 minimp3 未编译）
    uint8_t cart_size = 0;
    void yx5200_init(int samplerate) {}
    void yx5200_reset(void) {}
    void yx5200_write(unsigned int rx_data) {}
    void yx5200_update(unsigned int samples) {}
    int  yx5200_context_save(uint8 *state) { return 0; }
    int  yx5200_context_load(uint8 *state) { return 0; }
}

// load_archive：从文件系统加载文件到 buffer
int load_archive(char *filename, unsigned char *buffer, int maxsize, char *extension) {
    FILE *f = fopen(filename, "rb");
    if (!f) return 0;

    fseek(f, 0, SEEK_END);
    int size = (int)ftell(f);
    fseek(f, 0, SEEK_SET);

    if (size > maxsize) size = maxsize;
    int read = (int)fread(buffer, 1, size, f);
    fclose(f);

    // 返回扩展名（大写）
    if (extension) {
        const char *dot = strrchr(filename, '.');
        if (dot) {
            strncpy(extension, dot + 1, 3);
            extension[3] = 0;
            for (int i = 0; extension[i]; i++)
                extension[i] = (char)toupper((unsigned char)extension[i]);
        } else {
            extension[0] = 0;
        }
    }
    return read;
}

// ---- GG 屏幕尺寸 ----
static const int GG_WIDTH        = 160;
static const int GG_HEIGHT       = 144;
static const int GG_SAMPLE_RATE  = 44100;
static const int GG_BMP_WIDTH    = 720;  // Genesis-Plus-GX bitmap 内部宽度
static const int GG_BMP_HEIGHT   = 576;  // Genesis-Plus-GX bitmap 内部高度

// ---- 初始化 config 默认值 ----
static void gg_config_init(void) {
    memset(&config, 0, sizeof(config));
    config.hq_fm        = 1;
    config.hq_psg       = 0;
    config.filter       = 0;
    config.ym2612       = 0;   // MAME YM2612
    config.ym2413       = 1;
    config.psg_preamp   = 150;
    config.fm_preamp    = 100;
    config.cdda_volume  = 100;
    config.pcm_volume   = 100;
    config.lp_range     = 0x9999; // ~60%
    config.low_freq     = 200;
    config.high_freq    = 8000;
    config.lg           = 100;
    config.mg           = 100;
    config.hg           = 100;
    config.system       = 0;    // 自动检测
    config.region_detect = 0;   // 自动
    config.vdp_mode     = 0;    // 自动
    config.master_clock = 0;    // 自动
    config.force_dtack  = 0;
    config.addr_error   = 1;
    config.bios         = 0;    // 不使用 BIOS
    config.lock_on      = 0;
    config.add_on       = 0;
    config.overscan     = 0;
    config.aspect_ratio = 0;
    config.ntsc         = 0;
    config.lcd          = 0;    // 不模拟 GG LCD 效果
    config.gg_extra     = 0;
    config.left_border  = 0;
    config.render       = 0;
    config.no_sprite_limit = 1;
    config.enhanced_vscroll = 0;
    config.enhanced_vscroll_limit = 16;
    config.overclock    = 0;
    config.cd_latency   = 0;
    config.cd_precache  = 0;

    // 手柄配置
    config.input[0].device  = 0;
    config.input[0].port    = 0;
    config.input[0].padtype = 0;
}

@implementation GGBridgeObjC {
    std::vector<uint32_t> _frameBuffer;   // RGBA 输出
    std::vector<uint8_t>  _bmpData;       // Genesis-Plus-GX 内部 bitmap（RGB565 或 RGB888）
    std::vector<int16_t>  _audioBuffer;
    std::vector<int16_t>  _monoBuffer;
    int                   _audioSamples;
    BOOL                  _romLoaded;
    BOOL                  _initialized;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _frameBuffer.resize(GG_WIDTH * GG_HEIGHT, 0xFF000000);
        // bitmap 内部用 32bpp
        _bmpData.resize(GG_BMP_WIDTH * GG_BMP_HEIGHT * 4, 0);
        _audioBuffer.resize(4096 * 2, 0);
        _audioSamples = 0;
        _romLoaded    = NO;
        _initialized  = NO;
    }
    return self;
}

- (BOOL)loadROM:(NSData *)data {
    if (data.length == 0) return NO;

    // 写入临时文件（load_rom 需要文件路径）
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"game.gg"];
    if (![data writeToFile:tmpPath atomically:YES]) {
        NSLog(@"[GGBridge] 写临时文件失败");
        return NO;
    }

    // 初始化配置
    gg_config_init();

    // 初始化 bitmap（32bpp）
    memset(&bitmap, 0, sizeof(bitmap));
    bitmap.data   = _bmpData.data();
    bitmap.width  = GG_BMP_WIDTH;
    bitmap.height = GG_BMP_HEIGHT;
    bitmap.pitch  = GG_BMP_WIDTH * 4;  // 32bpp

    // 初始化音频
    if (audio_init(GG_SAMPLE_RATE, 0) < 0) {
        NSLog(@"[GGBridge] audio_init 失败");
        return NO;
    }

    // 加载 ROM
    char path[MAXPATHLEN];
    strncpy(path, tmpPath.UTF8String, MAXPATHLEN - 1);
    if (!load_rom(path)) {
        NSLog(@"[GGBridge] load_rom 失败");
        audio_shutdown();
        return NO;
    }

    // 配置输入：GG 使用 port 0 gamepad
    input.system[0] = SYSTEM_GAMEPAD;
    input.system[1] = NO_SYSTEM;
    input.dev[0]    = DEVICE_PAD2B;
    input.pad[0]    = 0;

    // 初始化系统
    system_init();
    audio_reset();
    system_reset();

    _romLoaded   = YES;
    _initialized = YES;
    NSLog(@"[GGBridge] ROM 加载成功 (%zu bytes), system_hw=0x%02x", data.length, system_hw);
    return YES;
}

- (void)runFrame {
    if (!_romLoaded) return;
    if (!snd.blips[0]) {
        audio_init(GG_SAMPLE_RATE, 0);
        audio_reset();
    }

    // 运行一帧（SMS/GG 使用 system_frame_sms）
    system_frame_sms(0);

    // 从 bitmap viewport 提取画面
    // USE_32BPP_RENDERING 模式下 Genesis-Plus-GX 输出 0xFFRRGGBB (ARGB)
    // Metal rgba8Unorm 需要 0xAABBGGRR (ABGR little-endian = RGBA bytes)
    int vx = bitmap.viewport.x;
    int vy = bitmap.viewport.y;
    int vw = bitmap.viewport.w;
    int vh = bitmap.viewport.h;

    int srcW = (vw > GG_WIDTH)  ? GG_WIDTH  : vw;
    int srcH = (vh > GG_HEIGHT) ? GG_HEIGHT : vh;
    int offX = (vw > GG_WIDTH)  ? (vw - GG_WIDTH)  / 2 : 0;
    int offY = (vh > GG_HEIGHT) ? (vh - GG_HEIGHT) / 2 : 0;

    for (int y = 0; y < srcH; y++) {
        const uint32_t *src = (const uint32_t *)(bitmap.data +
            ((vy + offY + y) * bitmap.pitch)) + (vx + offX);
        uint32_t *dst = _frameBuffer.data() + y * GG_WIDTH;
        for (int x = 0; x < srcW; x++) {
            uint32_t px = src[x]; // 0xFFRRGGBB
            uint32_t r = (px >> 16) & 0xFF;
            uint32_t g = (px >>  8) & 0xFF;
            uint32_t b =  px        & 0xFF;
            // Metal rgba8Unorm: R在低字节 → 0xFF_BB_GG_RR
            dst[x] = 0xFF000000 | (b << 16) | (g << 8) | r;
        }
    }

    // 获取音频
    _audioSamples = audio_update(_audioBuffer.data());
}

- (void)reset {
    if (_romLoaded) {
        audio_reset();
        system_reset();
    }
    input.pad[0] = 0;
}

- (const uint32_t *)getFrameBuffer { return _frameBuffer.data(); }
- (NSInteger)frameWidth            { return GG_WIDTH; }
- (NSInteger)frameHeight           { return GG_HEIGHT; }

- (void)setPlayer1Buttons:(uint16_t)buttons {
    // 映射 EmulatorButton → Genesis-Plus-GX INPUT_* (GG 2键手柄)
    // EmulatorButton: a=bit0, b=bit1, select=bit2, start=bit3, up=bit4, down=bit5, left=bit6, right=bit7
    uint16_t pad = 0;
    if (buttons & (1 << 4)) pad |= INPUT_UP;
    if (buttons & (1 << 5)) pad |= INPUT_DOWN;
    if (buttons & (1 << 6)) pad |= INPUT_LEFT;
    if (buttons & (1 << 7)) pad |= INPUT_RIGHT;
    if (buttons & (1 << 0)) pad |= INPUT_BUTTON1; // A → Button 1
    if (buttons & (1 << 1)) pad |= INPUT_BUTTON2; // B → Button 2
    if (buttons & (1 << 3)) pad |= INPUT_START;   // Start
    input.pad[0] = pad;
}

- (void)setPlayer2Buttons:(uint16_t)buttons {
    // GG 单人游戏，忽略 P2
}

- (const int16_t *)getAudioBuffer {
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
- (NSInteger)sampleRate          { return GG_SAMPLE_RATE; }

- (nullable NSData *)saveState {
    if (!_romLoaded) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:STATE_SIZE];
    int saved = state_save((unsigned char *)data.mutableBytes);
    if (saved <= 0) return nil;
    return [data subdataWithRange:NSMakeRange(0, saved)];
}

- (BOOL)loadState:(NSData *)data {
    if (!_romLoaded || data.length == 0) return NO;
    // state_load 需要固定大小缓冲区
    NSMutableData *buf = [NSMutableData dataWithLength:STATE_SIZE];
    memcpy(buf.mutableBytes, data.bytes, MIN(data.length, STATE_SIZE));
    return state_load((unsigned char *)buf.mutableBytes) > 0;
}

- (void)writeByte:(uint8_t)value at:(uint32_t)address {
    if (!_romLoaded) return;
    // SMS/GG Z80 RAM: 0xC000-0xDFFF，映射到 zram[0x0000-0x1FFF]
    if (address >= 0xC000 && address <= 0xDFFF) {
        zram[address & 0x1FFF] = value;
    }
}

@end
