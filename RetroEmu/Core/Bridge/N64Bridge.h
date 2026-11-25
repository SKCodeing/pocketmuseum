// N64Bridge.h
// Mupen64Plus Nintendo 64 核心桥接头文件
// Sprint 6: N64 平台支持
//
// 注意：iOS 不允许 JIT，使用解释器模式（性能约为 JIT 的 1/5）
// 建议设备：iPhone 13+ 可流畅运行大多数游戏

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface N64BridgeObjC : NSObject

- (BOOL)loadROM:(NSData *)data;
- (void)runFrame;
- (void)reset;
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

@end

NS_ASSUME_NONNULL_END
