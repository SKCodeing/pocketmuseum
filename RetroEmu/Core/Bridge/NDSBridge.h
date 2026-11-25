// NDSBridge.h
// melonDS Nintendo DS 核心桥接头文件
// Sprint 2: NDS 平台支持

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NDSBridgeObjC : NSObject

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

/// NDS 触摸屏输入（归一化坐标 0.0~1.0，对应下屏）
- (void)touchScreenAt:(float)x y:(float)y;
- (void)touchScreenRelease;

@end

NS_ASSUME_NONNULL_END
