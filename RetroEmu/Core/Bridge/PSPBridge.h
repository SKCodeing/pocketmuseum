// PSPBridge.h
// PPSSPP PlayStation Portable 核心桥接头文件
// Vulkan/MoltenVK 硬件渲染（通过 CAMetalLayer）

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

@interface PSPBridgeObjC : NSObject

/// 必须在 loadROM 之前设置 Metal layer（PPSSPP 直接渲染到此 layer）
@property (nonatomic, strong, nullable) CAMetalLayer *metalLayer;

- (BOOL)loadROM:(NSData *)data filename:(NSString *)filename;
- (BOOL)loadROMFromPath:(NSString *)path;
- (void)runFrame;
- (void)reset;

/// Vulkan 模式下返回 nil（画面直接渲染到 metalLayer）
- (const uint32_t * _Nullable)getFrameBuffer;
- (NSInteger)frameWidth;
- (NSInteger)frameHeight;

- (void)setPlayer1Buttons:(uint16_t)buttons;
- (void)setPlayer2Buttons:(uint16_t)buttons;
- (const int16_t * _Nullable)getAudioBuffer;
- (NSInteger)audioSampleCount;
- (NSInteger)sampleRate;
- (nullable NSData *)saveState;
- (BOOL)loadState:(NSData *)data;
- (void)writeByte:(uint8_t)value at:(uint32_t)address;
- (void)setRenderScale:(NSInteger)scale;

@property (nonatomic) BOOL useJIT;

@end

NS_ASSUME_NONNULL_END
